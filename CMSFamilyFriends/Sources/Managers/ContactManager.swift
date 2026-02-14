import Foundation
import Contacts
import EventKit
import Combine

/// Zentrale Manager-Klasse für Kontakt-Tracking
@MainActor
class ContactManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isTracking = false
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [SyncError] = []
    
    // MARK: - Data Source Services
    private let calendarService = CalendarService()
    private let contactsService = ContactsService()
    private let messageService = MessageService()
    private let callHistoryService = CallHistoryService()
    private let whatsAppService = WhatsAppService()
    private let mailService = MailService()
    
    // MARK: - Tracking Timer
    private var syncTimer: Timer?
    private let syncIntervalMinutes: Double = 30
    
    // MARK: - Lifecycle
    
    /// Startet das automatische Tracking
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        // Initialer Sync
        Task {
            await performSync()
        }
        
        // Timer für regelmäßigen Sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalMinutes * 60, repeats: true) { [weak self] _ in
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
    
    // MARK: - Sync
    
    /// Führt einen vollständigen Sync aller Datenquellen durch
    func performSync() async {
        syncErrors.removeAll()
        
        // Paralleler Sync aller Datenquellen
        await withTaskGroup(of: SyncError?.self) { group in
            group.addTask { await self.syncCalendarEvents() }
            group.addTask { await self.syncContacts() }
            group.addTask { await self.syncMessages() }
            group.addTask { await self.syncCallHistory() }
            group.addTask { await self.syncWhatsApp() }
            group.addTask { await self.syncMail() }
            
            for await error in group {
                if let error = error {
                    syncErrors.append(error)
                }
            }
        }
        
        lastSyncDate = Date()
    }
    
    // MARK: - Individual Syncs
    
    private func syncCalendarEvents() async -> SyncError? {
        do {
            let events = try await calendarService.fetchRecentEvents()
            // TODO: Events mit Kontakten matchen und CommunicationEvents erstellen
            print("📅 \(events.count) Kalender-Events gefunden")
            return nil
        } catch {
            return SyncError(source: .calendar, message: error.localizedDescription)
        }
    }
    
    private func syncContacts() async -> SyncError? {
        do {
            let contacts = try await contactsService.fetchAllContacts()
            // TODO: Kontakte importieren/aktualisieren
            print("👤 \(contacts.count) Kontakte gefunden")
            return nil
        } catch {
            return SyncError(source: .calendar, message: error.localizedDescription)
        }
    }
    
    private func syncMessages() async -> SyncError? {
        do {
            let messages = try await messageService.fetchRecentMessages()
            print("💬 \(messages.count) iMessages gefunden")
            return nil
        } catch {
            return SyncError(source: .imessage, message: error.localizedDescription)
        }
    }
    
    private func syncCallHistory() async -> SyncError? {
        do {
            let calls = try await callHistoryService.fetchRecentCalls()
            print("📞 \(calls.count) Anrufe gefunden")
            return nil
        } catch {
            return SyncError(source: .phone, message: error.localizedDescription)
        }
    }
    
    private func syncWhatsApp() async -> SyncError? {
        do {
            let messages = try await whatsAppService.fetchRecentMessages()
            print("📱 \(messages.count) WhatsApp-Nachrichten gefunden")
            return nil
        } catch {
            return SyncError(source: .whatsapp, message: error.localizedDescription)
        }
    }
    
    private func syncMail() async -> SyncError? {
        do {
            let emails = try await mailService.fetchRecentEmails()
            print("📧 \(emails.count) E-Mails gefunden")
            return nil
        } catch {
            return SyncError(source: .email, message: error.localizedDescription)
        }
    }
}

// MARK: - Sync Error
struct SyncError: Identifiable {
    let id = UUID()
    let source: CommunicationChannel
    let message: String
    let timestamp = Date()
}
