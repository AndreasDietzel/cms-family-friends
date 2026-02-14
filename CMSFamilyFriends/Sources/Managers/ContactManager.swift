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
        
        let mailAccess = await mailService.checkAccess()
        dataSourceStatuses[.email] = mailAccess ? .connected : .needsAccess
        
        dataSourceStatuses[.facetime] = .disabled
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
            group.addTask { await (.calendar, self.syncCalendarEvents()) }
            group.addTask { await (.contacts, self.syncContacts()) }
            group.addTask { await (.imessage, self.syncMessages()) }
            group.addTask { await (.phone, self.syncCallHistory()) }
            group.addTask { await (.whatsapp, self.syncWhatsApp()) }
            group.addTask { await (.email, self.syncMail()) }
            
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
    
    // MARK: - Individual Syncs
    
    private func syncCalendarEvents() async -> Result<Int, Error> {
        do { return .success(try await calendarService.fetchRecentEvents().count) }
        catch { return .failure(error) }
    }
    
    private func syncContacts() async -> Result<Int, Error> {
        do { return .success(try await contactsService.fetchAllContacts().count) }
        catch { return .failure(error) }
    }
    
    private func syncMessages() async -> Result<Int, Error> {
        do { return .success(try await messageService.fetchRecentMessages().count) }
        catch { return .failure(error) }
    }
    
    private func syncCallHistory() async -> Result<Int, Error> {
        do { return .success(try await callHistoryService.fetchRecentCalls().count) }
        catch { return .failure(error) }
    }
    
    private func syncWhatsApp() async -> Result<Int, Error> {
        do { return .success(try await whatsAppService.fetchRecentMessages().count) }
        catch { return .failure(error) }
    }
    
    private func syncMail() async -> Result<Int, Error> {
        do { return .success(try await mailService.fetchRecentEmails().count) }
        catch { return .failure(error) }
    }
}

// MARK: - Sync Error (mit DataSource statt CommunicationChannel)
struct SyncError: Identifiable {
    let id = UUID()
    let source: DataSource
    let message: String
    let timestamp = Date()
}
