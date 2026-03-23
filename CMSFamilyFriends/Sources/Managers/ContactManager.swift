import Foundation
import Contacts
import EventKit
import Combine
import SwiftData
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
    
    /// SwiftData ModelContext – muss von einer View gesetzt werden
    var modelContext: ModelContext?
    
    // MARK: - Data Source Services
    // Hinweis: CalendarService und MailService nicht mehr verwendet –
    // Es werden ausschließlich direkte Kontakte (Chat, Telefon, Video) synchronisiert.
    private let contactsService = ContactsService()
    private let messageService = MessageService()
    private let callHistoryService = CallHistoryService()
    private let whatsAppService = WhatsAppService()
    
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
        // E-Mail und Kalender werden nicht mehr synchronisiert (nur direkter Kontakt)
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
    
    // MARK: - Contact Lookup
    
    /// Lookup-Tabelle für schnelles Matching: Phone/Email/Name → TrackedContact
    private struct ContactLookupTable {
        var byPhone: [String: TrackedContact] = [:]
        var byEmail: [String: TrackedContact] = [:]
        var byName: [String: TrackedContact] = [:]
    }
    
    /// Telefonnummer für Matching normalisieren (letzte 10 Ziffern)
    private func normalizePhone(_ number: String) -> String {
        let digits = number.filter(\.isNumber)
        if digits.count > 10 {
            return String(digits.suffix(10))
        }
        return digits
    }
    
    /// Lookup-Tabelle aufbauen: TrackedContacts → Apple Contacts → Phone/Email Mapping
    private func buildLookups(trackedContacts: [TrackedContact]) async -> ContactLookupTable {
        var lookups = ContactLookupTable()
        
        // Name-basiertes Matching für alle Kontakte
        for contact in trackedContacts {
            let key = "\(contact.firstName) \(contact.lastName)".lowercased().trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && key != " " {
                lookups.byName[key] = contact
            }
        }
        
        // Phone/Email via Apple Contacts
        do {
            let appleContacts = try await contactsService.fetchAllContacts()
            dataSourceStatuses[.contacts] = .connected
            lastSyncResults[.contacts] = appleContacts.count
            AppLogger.syncCompleted(source: .contacts, itemCount: appleContacts.count)
            
            for tracked in trackedContacts {
                guard let appleId = tracked.appleContactIdentifier else { continue }
                guard let apple = appleContacts.first(where: { $0.identifier == appleId }) else { continue }
                
                for phone in apple.phoneNumbers {
                    let normalized = normalizePhone(phone)
                    if !normalized.isEmpty {
                        lookups.byPhone[normalized] = tracked
                    }
                }
                for email in apple.emailAddresses {
                    lookups.byEmail[email.lowercased()] = tracked
                }
            }
        } catch {
            syncErrors.append(SyncError(source: .contacts, message: error.localizedDescription))
            if let serviceError = error as? ServiceError {
                switch serviceError {
                case .notAuthorized: dataSourceStatuses[.contacts] = .needsAccess
                default: dataSourceStatuses[.contacts] = .unavailable(reason: "Fehler")
                }
            }
            AppLogger.syncFailed(source: .contacts, error: error)
        }
        
        return lookups
    }
    
    /// Kontakt per Phone, Email oder Name matchen
    private func matchContact(phone: String? = nil, email: String? = nil, name: String? = nil, lookups: ContactLookupTable) -> TrackedContact? {
        if let phone, !phone.isEmpty {
            let normalized = normalizePhone(phone)
            if !normalized.isEmpty, let contact = lookups.byPhone[normalized] {
                return contact
            }
        }
        if let email, !email.isEmpty {
            if let contact = lookups.byEmail[email.lowercased()] {
                return contact
            }
        }
        if let name, !name.isEmpty {
            if let contact = lookups.byName[name.lowercased()] {
                return contact
            }
        }
        return nil
    }
    
    // MARK: - Sync (mit Event-Import, Matching & Deduplizierung)
    
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
        
        guard let modelContext else {
            isSyncing = false
            return
        }
        
        // 1. Alle TrackedContacts laden
        let trackedContacts: [TrackedContact]
        do {
            trackedContacts = try modelContext.fetch(FetchDescriptor<TrackedContact>())
        } catch {
            isSyncing = false
            return
        }
        
        guard !trackedContacts.isEmpty else {
            isSyncing = false
            lastSyncDate = Date()
            return
        }
        
        // 2. Lookup-Tabelle aufbauen (Phone/Email/Name → TrackedContact)
        let lookups = await buildLookups(trackedContacts: trackedContacts)
        
        // 3a. Einmalige Bereinigung alter WhatsApp-Status-Events
        await performWhatsAppStatusCleanupIfNeeded(trackedContacts: trackedContacts)
        
        // 3a.2 Laufende Bereinigung: Alte auto-importierte WhatsApp-Events
        //       vor jedem Sync entfernen und danach sauber neu importieren.
        await performWhatsAppAutoRefreshCleanup(trackedContacts: trackedContacts)
        
        // 3b. Einmalige Bereinigung von E-Mail- und Kalender-Events
        //     (werden nicht mehr synchronisiert – nur direkter Kontakt)
        await performEmailCalendarCleanupIfNeeded(trackedContacts: trackedContacts)
        
        // 4. Existierende sourceIdentifiers laden für Deduplizierung
        //    (nach Bereinigung: sauber, keine gelöschten WA-IDs drin)
        let existingIds: Set<String>
        do {
            let events = try modelContext.fetch(FetchDescriptor<CommunicationEvent>())
            existingIds = Set(events.compactMap(\.sourceIdentifier))
        } catch {
            existingIds = []
        }
        
        // 5. Letztes Kontaktdatum pro Kontakt tracken
        var latestDates: [UUID: Date] = [:]
        for contact in trackedContacts {
            if let date = contact.lastContactDate {
                latestDates[contact.id] = date
            }
        }
        
        // 6. Events aus allen Quellen importieren
        
        // --- Telefon & FaceTime ---
        do {
            let calls = try await withTimeout(seconds: 15) {
                try await self.callHistoryService.fetchRecentCalls()
            }
            var phoneCount = 0
            var faceTimeCount = 0
            
            for call in calls {
                let sourceId = "call-\(call.identifier)"
                guard !existingIds.contains(sourceId) else { continue }
                guard let contact = matchContact(phone: call.phoneNumber, lookups: lookups) else { continue }
                
                let channel: CommunicationChannel = call.isFaceTime ? .facetime : .phone
                let event = CommunicationEvent(
                    channel: channel,
                    direction: call.isOutgoing ? .outgoing : .incoming,
                    date: call.date,
                    durationSeconds: Int(call.duration),
                    isAutoDetected: true,
                    sourceIdentifier: sourceId
                )
                event.contact = contact
                modelContext.insert(event)
                
                if call.isFaceTime { faceTimeCount += 1 } else { phoneCount += 1 }
                updateLatestDate(&latestDates, contactId: contact.id, date: call.date)
            }
            
            lastSyncResults[.phone] = phoneCount
            lastSyncResults[.facetime] = faceTimeCount
            dataSourceStatuses[.phone] = .connected
            dataSourceStatuses[.facetime] = .connected
            AppLogger.syncCompleted(source: .phone, itemCount: phoneCount)
            AppLogger.syncCompleted(source: .facetime, itemCount: faceTimeCount)
        } catch {
            handleSyncError(.phone, error)
            handleSyncError(.facetime, error)
        }
        
        // --- iMessage ---
        do {
            let messages = try await withTimeout(seconds: 15) {
                try await self.messageService.fetchRecentMessages()
            }
            var count = 0
            
            for msg in messages {
                let sourceId = "imsg-\(msg.rowId)"
                guard !existingIds.contains(sourceId) else { continue }
                guard let contact = matchContact(phone: msg.handleId, email: msg.handleId, lookups: lookups) else { continue }
                
                let event = CommunicationEvent(
                    channel: .imessage,
                    direction: msg.isFromMe ? .outgoing : .incoming,
                    date: msg.date,
                    isAutoDetected: true,
                    sourceIdentifier: sourceId
                )
                event.contact = contact
                modelContext.insert(event)
                count += 1
                updateLatestDate(&latestDates, contactId: contact.id, date: msg.date)
            }
            
            lastSyncResults[.imessage] = count
            dataSourceStatuses[.imessage] = .connected
            AppLogger.syncCompleted(source: .imessage, itemCount: count)
        } catch {
            handleSyncError(.imessage, error)
        }
        
        // --- WhatsApp ---
        do {
            let messages = try await withTimeout(seconds: 15) {
                try await self.whatsAppService.fetchRecentMessages()
            }
            var count = 0
            
            for msg in messages {
                let sourceId = "wa-\(msg.messageId)"
                guard !existingIds.contains(sourceId) else { continue }
                guard let contact = matchContact(
                    phone: msg.contactNumber,
                    name: msg.contactName,
                    lookups: lookups
                ) else { continue }
                
                let event = CommunicationEvent(
                    channel: .whatsapp,
                    direction: msg.isFromMe ? .outgoing : .incoming,
                    date: msg.date,
                    isAutoDetected: true,
                    sourceIdentifier: sourceId
                )
                event.contact = contact
                modelContext.insert(event)
                count += 1
                updateLatestDate(&latestDates, contactId: contact.id, date: msg.date)
            }
            
            lastSyncResults[.whatsapp] = count
            dataSourceStatuses[.whatsapp] = .connected
            AppLogger.syncCompleted(source: .whatsapp, itemCount: count)
        } catch {
            handleSyncError(.whatsapp, error)
        }
        
        // 6. lastContactDate für alle Kontakte aktualisieren
        let now = Date()
        for contact in trackedContacts {
            // Korrupte Zukunftsdaten zurücksetzen (z.B. durch fehlerhafte Timestamp-Interpretation)
            if let existing = contact.lastContactDate, existing > now {
                contact.lastContactDate = nil
            }
            if let latestDate = latestDates[contact.id], latestDate <= now {
                if let existing = contact.lastContactDate {
                    if latestDate > existing {
                        contact.lastContactDate = latestDate
                    }
                } else {
                    contact.lastContactDate = latestDate
                }
            }
        }
        
        // 7. Speichern
        do {
            try modelContext.save()
        } catch {
            syncErrors.append(SyncError(source: .contacts, message: "Fehler beim Speichern: \(error.localizedDescription)"))
            AppLogger.syncFailed(source: .contacts, error: error)
        }
        
        lastSyncDate = Date()
        isSyncing = false
    }
    
    // MARK: - Data Cleanup Migrations

    /// Löscht einmalig alle vorhandenen E-Mail- und Kalender-Events.
    /// Diese Kanäle werden nicht mehr synchronisiert (nur direkter Kontakt: Chat, Telefon, Video).
    private func performEmailCalendarCleanupIfNeeded(trackedContacts: [TrackedContact]) async {
        let flagKey = "emailCalendarCleanupV1Done"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let modelContext else { return }

        do {
            let eventsToDelete = try modelContext.fetch(
                FetchDescriptor<CommunicationEvent>(
                    predicate: #Predicate { $0.channelRawValue == "email" || $0.channelRawValue == "calendar" }
                )
            )
            guard !eventsToDelete.isEmpty else {
                UserDefaults.standard.set(true, forKey: flagKey)
                return
            }

            let affectedContacts = Set(eventsToDelete.compactMap(\.contact))

            for event in eventsToDelete {
                modelContext.delete(event)
            }

            // lastContactDate aus verbleibenden direkten Kontakt-Events neu berechnen
            let directChannels: Set<String> = ["phone", "facetime", "imessage", "whatsapp", "reallife", "manual"]
            for contact in affectedContacts {
                let remaining = contact.communicationEvents.filter { directChannels.contains($0.channelRawValue) }
                contact.lastContactDate = remaining.map(\.date).filter { $0 <= Date() }.max()
            }

            UserDefaults.standard.set(true, forKey: flagKey)
            AppLogger.contactOperation(
                "E-Mail/Kalender-Bereinigung: \(eventsToDelete.count) Events entfernt, \(affectedContacts.count) Kontakte aktualisiert",
                count: eventsToDelete.count
            )
            try? modelContext.save()
        } catch {
            AppLogger.syncFailed(source: .email, error: error)
        }
    }

    // MARK: - WhatsApp Status Cleanup

    /// V3-Migration: Löscht alle vorhandenen WhatsApp-Events aus der DB und
    /// lässt sie beim nächsten Sync sauber reimportieren (ohne Status-Stories).
    /// Supersedes V1/V2 – in der Praxis treten Status-Einträge auch als
    /// kontaktbezogene JIDs mit Suffix @status auf (z.B. 4917...@status).
    private func performWhatsAppStatusCleanupIfNeeded(trackedContacts: [TrackedContact]) async {
        let flagKey = "whatsappStatusCleanupV3Done"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let modelContext else { return }

        do {
            let allWAEvents = try modelContext.fetch(
                FetchDescriptor<CommunicationEvent>(
                    predicate: #Predicate { $0.channelRawValue == "whatsapp" }
                )
            )
            // V1-Flag ebenfalls setzen, damit V1 nicht nochmals läuft
            UserDefaults.standard.set(true, forKey: "whatsappStatusCleanupV1Done")
            UserDefaults.standard.set(true, forKey: "whatsappStatusCleanupV2Done")

            guard !allWAEvents.isEmpty else {
                UserDefaults.standard.set(true, forKey: flagKey)
                return
            }

            // Betroffene Kontakte sammeln
            let affectedContacts = Set(allWAEvents.compactMap(\.contact))

            // Alle WA-Events löschen (inkl. bislang durchgerutschter Status-Events)
            for event in allWAEvents {
                modelContext.delete(event)
            }

            // lastContactDate aus verbleibenden direkten Kontakt-Events neu berechnen
            let directChannels: Set<String> = ["phone", "facetime", "imessage", "reallife", "manual"]
            for contact in affectedContacts {
                let remaining = contact.communicationEvents.filter { directChannels.contains($0.channelRawValue) }
                contact.lastContactDate = remaining.map(\.date).filter { $0 <= Date() }.max()
            }

            UserDefaults.standard.set(true, forKey: flagKey)
            AppLogger.contactOperation(
                "WhatsApp V3-Bereinigung: \(allWAEvents.count) Events entfernt (inkl. @status), \(affectedContacts.count) Kontakte aktualisiert",
                count: allWAEvents.count
            )
            // Sofort committen – damit das nachfolgende existingIds-Fetch
            // die gelöschten WA-Events nicht mehr sieht.
            try? modelContext.save()
        } catch {
            AppLogger.syncFailed(source: .whatsapp, error: error)
        }
    }

    /// Löscht bei jedem Sync alle automatisch importierten WhatsApp-Events,
    /// damit nur noch die aktuell gefilterten Direktkontakte sichtbar sind.
    /// Manuelle WhatsApp-Einträge (isAutoDetected == false) bleiben erhalten.
    private func performWhatsAppAutoRefreshCleanup(trackedContacts: [TrackedContact]) async {
        guard let modelContext else { return }

        do {
            let allWAEvents = try modelContext.fetch(
                FetchDescriptor<CommunicationEvent>(
                    predicate: #Predicate { $0.channelRawValue == "whatsapp" }
                )
            )
            // Robust filtern (in-memory), damit keine Predicate-Übersetzung zu false negatives führt.
            // Importierte WA-Events erkennen wir an isAutoDetected oder sourceIdentifier mit Prefix "wa-".
            let importedWAEvents = allWAEvents.filter {
                $0.isAutoDetected || ($0.sourceIdentifier?.hasPrefix("wa-") ?? false)
            }
            guard !importedWAEvents.isEmpty else { return }

            let affectedContacts = Set(importedWAEvents.compactMap(\.contact))

            for event in importedWAEvents {
                modelContext.delete(event)
            }

            // lastContactDate aus verbleibenden direkten Kontakt-Events neu berechnen
            let directChannels: Set<String> = ["phone", "facetime", "imessage", "reallife", "manual", "whatsapp"]
            for contact in affectedContacts {
                let remaining = contact.communicationEvents.filter { directChannels.contains($0.channelRawValue) }
                contact.lastContactDate = remaining.map(\.date).filter { $0 <= Date() }.max()
            }

            try? modelContext.save()
            AppLogger.contactOperation(
                "WhatsApp-Refresh: \(importedWAEvents.count) importierte Events entfernt (werden sauber neu importiert)",
                count: importedWAEvents.count
            )
        } catch {
            AppLogger.syncFailed(source: .whatsapp, error: error)
        }
    }

    // MARK: - Helpers

    private func updateLatestDate(_ dates: inout [UUID: Date], contactId: UUID, date: Date) {
        // Zukunftsdaten ignorieren – können durch fehlerhafte Timestamps entstehen
        guard date <= Date() else { return }
        if let existing = dates[contactId] {
            if date > existing { dates[contactId] = date }
        } else {
            dates[contactId] = date
        }
    }
    
    private func handleSyncError(_ source: DataSource, _ error: Error) {
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
    
    /// Timeout-geschützte Operation (gibt Ergebnis statt nur Count zurück)
    private func withTimeout<T: Sendable>(seconds: Int, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ServiceError.notAvailable("Timeout nach \(seconds) Sekunden")
            }
            guard let first = try await group.next() else {
                throw ServiceError.notAvailable("Interner Fehler bei Timeout-Verarbeitung")
            }
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Sync Error
struct SyncError: Identifiable {
    let id = UUID()
    let source: DataSource
    let message: String
    let timestamp = Date()
}
