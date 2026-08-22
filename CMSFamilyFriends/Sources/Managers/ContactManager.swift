import Foundation
import Contacts
import Combine
import SwiftData
import os.log

/// Zentrale Manager-Klasse für Kontakt-Tracking.
/// Hält ausschließlich UI-State (@Published). Alle schweren DB-Operationen
/// laufen via SyncActor off-main-thread – die Navigation bleibt jederzeit
/// reaktionsfähig, auch während ein Sync läuft.
@MainActor
class ContactManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isTracking = false
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [SyncError] = []
    @Published var isSyncing = false
    @Published var dataSourceStatuses: [DataSource: DataSourceStatus] = [:]
    @Published var lastSyncResults: [DataSource: Int] = [:]

    // MARK: - Services (actors – thread-safe, Sendable)
    private let contactsService = ContactsService()
    private let messageService = MessageService()
    private let callHistoryService = CallHistoryService()
    private let whatsAppService = WhatsAppService()

    // MARK: - Background Sync
    private var syncActor: SyncActor?
    
    // MARK: - Timer & Rate-Limiting
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

    /// ModelContainer übergeben (einmalig aus ContentView).
    /// Erstellt den SyncActor mit eigenem Background-ModelContext.
    func setContainer(_ container: ModelContainer) {
        guard syncActor == nil else { return }
        syncActor = SyncActor(
            modelContainer: container,
            messageService: messageService,
            callHistoryService: callHistoryService,
            whatsAppService: whatsAppService,
            contactsService: contactsService
        )
    }

    /// Startet das automatische Tracking
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        AppLogger.syncStarted()
        Task {
            // Kurz warten: SwiftUI beendet seinen ersten Render-Pass,
            // bevor der erste Sync startet.
            try? await Task.sleep(for: .seconds(3))
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

    // MARK: - Data Source Availability

    func checkDataSourceAvailability() async {
        dataSourceStatuses[.email] = .disabled
        dataSourceStatuses[.calendar] = .disabled
        dataSourceStatuses[.contacts] = .checking
        let messageAccess = await messageService.checkAccess()
        dataSourceStatuses[.imessage] = messageAccess ? .connected : .needsAccess
        let whatsAppAccess = await whatsAppService.checkAccess()
        dataSourceStatuses[.whatsapp] = whatsAppAccess ? .connected : .unavailable(reason: "Nicht installiert")
        let callAccess = await callHistoryService.checkAccess()
        dataSourceStatuses[.phone] = callAccess ? .connected : .needsAccess
        dataSourceStatuses[.facetime] = callAccess ? .connected : .needsAccess
    }

    // MARK: - Sync

    func performSync() async {
        if let lastStart = lastSyncStartTime,
           Date().timeIntervalSince(lastStart) < minimumSyncIntervalSeconds { return }
        guard !isSyncing else { return }
        guard let syncActor else { return }

        isSyncing = true
        lastSyncStartTime = Date()
        syncErrors.removeAll()
        lastSyncResults.removeAll()
        AppLogger.syncStarted()

        // Sync-Fenster bestimmen
        let syncDaysPast: Int
        let idCutoffDate: Date
        if let lastSync = lastSyncDate {
            let daysSince = max(1, Int(Date().timeIntervalSince(lastSync) / 86400) + 1)
            syncDaysPast = min(daysSince, 90)
            idCutoffDate = lastSync.addingTimeInterval(-300)
        } else {
            syncDaysPast = 90
            idCutoffDate = Date().addingTimeInterval(-90 * 86400)
        }

        // Gesamter Sync läuft off-main-thread im SyncActor
        let result = await syncActor.performSync(
            syncDaysPast: syncDaysPast,
            idCutoffDate: idCutoffDate
        )

        // UI-State auf @MainActor aktualisieren
        syncErrors = result.errors
        for (source, status) in result.statuses {
            dataSourceStatuses[source] = status
        }
        for (source, count) in result.counts {
            lastSyncResults[source] = count
        }
        lastSyncDate = Date()
        isSyncing = false
    }
}

// MARK: - Sync Error
struct SyncError: Identifiable, Sendable {
    let id = UUID()
    let source: DataSource
    let message: String
    let timestamp = Date()
}
