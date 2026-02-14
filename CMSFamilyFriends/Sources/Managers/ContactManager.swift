import Foundation
import Contacts
import EventKit
import Combine
import os.log

/// Zentrale Manager-Klasse für Kontakt-Tracking
/// ISO 25010: Logging statt print(), Rate-Limiting, Graceful Degradation, dynamischer Status
@MainActor
class ContactManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isTracking = false
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [SyncError] = []
    @Published var isSyncing = false
    @Published var dataSourceStatuses: [DataSource: DataSourceStatus] = [:]
    @Published var lastSyncResults: [DataSource: Int] = [:]
    
    // MARK: - Data Source Services
    private let calendarService = CalendarService()
    private let contactsService = ContactsService()
    private let messageService = MessageService()
    private let callHistoryService = CallHistoryService()
    private let whatsAppService = WhatsAppService()
    private let mailService = MailService()
    
    // MARK: - Tracking Timer & Rate-Limiting
    private var syncTimer: Timer?
    private var lastSyncStartTime: Date?
    private let minimumSyncIntervalSeconds: TimeInterval = 60
    
    var syncIntervalMinutes: Double {
        Double(max(15, min(120, UserDefaults.standard.integer(forKey: "syncIntervalMinutes"))))
    }
    
    // MARK: - Lifecycle
    
    init() {
        for source in DataSource.allCases {
            dataSourceStatuses[source] = .checking
        }
    }
    
    /// Startet das automatische Tracking
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        AppLogger.syncStarted()
        
        Task {
            await checkDataSourceAvailability()
            await performSync()
        }
        
        let interval = max(syncIntervalMinutes, 15) * 60
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performSync()
            }
        }
    }
    
    /// Stoppt das Tracking
    func stopTracking() {
        isTracking = false
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Data Source Availability Check
    
    func checkDataSourceAvailability() async {
        dataSourceStatuses[.calendar] = .checking
        dataSourceStatuses[.contacts] = .checking
        
        let messageAccess = await messageService.checkAccess()
        dataSourceStatuses[.imessage] = messageAccess ? .connected : .needsAccess
        
        let whatsAppAccess = await whatsAppService.checkAccess()
        dataSourceStatuses[.whatsapp] = whatsAppAccess ? .connected : .unavailable(reason: "Nicht installiert")
        
        let callAccess = await callHistoryService.checkAccess()
        dataSourceStatuses[.phone] = callAccess ? .connected : .needsAccess
        
        // FaceTime nutzt dieselbe DB wie Telefon
        dataSourceStatuses[.facetime] = callAccess ? .connected : .needsAccess
        
        let mailAccess = await mailService.checkAccess()
        dataSourceStatuses[.email] = mailAccess ? .connected : .needsAccess
    }
    
    // MARK: - Sync (mit Rate-Limiting & Graceful Degradation)
    
    func performSync() async {
        if let lastStart = lastSyncStartTime,
           Date().timeIntervalSince(lastStart) < minimumSyncIntervalSeconds {
            return
        }
        
        guard !isSyncing else { return }
        isSyncing = true
        lastSyncStartTime = Date()
        syncErrors.removeAll()
        lastSyncResults.removeAll()
        
        AppLogger.syncStarted()
        
        await withTaskGroup(of: (DataSource, Result<Int, Error>).self) { group in
            group.addTask { (.calendar, await self.withTimeout(seconds: 10) { try await self.calendarService.fetchRecentEvents().count }) }
            group.addTask { (.contacts, await self.withTimeout(seconds: 10) { try await self.contactsService.fetchAllContacts().count }) }
            group.addTask { (.imessage, await self.withTimeout(seconds: 10) { try await self.messageService.fetchRecentMessages().count }) }
            group.addTask { (.phone, await self.withTimeout(seconds: 10) { try await self.callHistoryService.fetchPhoneCalls().count }) }
            group.addTask { (.whatsapp, await self.withTimeout(seconds: 10) { try await self.whatsAppService.fetchRecentMessages().count }) }
            group.addTask { (.email, await self.withTimeout(seconds: 10) { try await self.mailService.fetchRecentEmails().count }) }
            group.addTask { (.facetime, await self.withTimeout(seconds: 10) { try await self.callHistoryService.fetchFaceTimeCalls().count }) }
            
            for await (source, result) in group {
                switch result {
                case .success(let count):
                    lastSyncResults[source] = count
                    dataSourceStatuses[source] = .connected
                    AppLogger.syncCompleted(source: source, itemCount: count)
                case .failure(let error):
                    syncErrors.append(SyncError(source: source, message: error.localizedDescription))
                    if let serviceError = error as? ServiceError {
                        switch serviceError {
                        case .notAuthorized:
                            dataSourceStatuses[source] = .needsAccess
                        case .notAvailable(let msg):
                            dataSourceStatuses[source] = .unavailable(reason: msg)
                        default:
                            dataSourceStatuses[source] = .unavailable(reason: "Fehler")
                        }
                    }
                    AppLogger.syncFailed(source: source, error: error)
                }
            }
        }
        
        lastSyncDate = Date()
        isSyncing = false
    }
    
    // MARK: - Timeout Helper
    
    /// Führt eine async Operation mit Timeout aus
    private func withTimeout(seconds: Int, operation: @Sendable @escaping () async throws -> Int) async -> Result<Int, Error> {
        do {
            let result = try await withThrowingTaskGroup(of: Int.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(seconds))
                    throw ServiceError.notAvailable("Timeout nach \(seconds) Sekunden")
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Sync Error (mit DataSource statt CommunicationChannel)
struct SyncError: Identifiable {
    let id = UUID()
    let source: DataSource
    let message: String
    let timestamp = Date()
}
