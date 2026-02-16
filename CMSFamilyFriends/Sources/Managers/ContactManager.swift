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
    
    /// Sync-Timer mit neuem Intervall neu starten (z.B. nach Settings-Änderung)
    func updateSyncInterval() {
        guard isTracking else { return }
        syncTimer?.invalidate()
        let interval = max(syncIntervalMinutes, 15) * 60
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performSync()
            }
        }
    }
    
    // MARK: - Data Source Availability Check
    
    func checkDataSourceAvailability() async {
        dataSourceStatuses[.calendar] = .checking
        dataSourceStatuses[.contacts] = .checking
        
        // Kalender-Zugriff prüfen
        do {
            let calendarAccess = try await calendarService.requestAccess()
            dataSourceStatuses[.calendar] = calendarAccess ? .connected : .needsAccess
        } catch {
            if let serviceError = error as? ServiceError, case .notAuthorized = serviceError {
                dataSourceStatuses[.calendar] = .needsAccess
            } else {
                dataSourceStatuses[.calendar] = .unavailable(reason: "Fehler")
            }
        }
        
        // Kontakte-Zugriff prüfen
        do {
            let contactsAccess = try await contactsService.requestAccess()
            dataSourceStatuses[.contacts] = contactsAccess ? .connected : .needsAccess
        } catch {
            if let serviceError = error as? ServiceError, case .notAuthorized = serviceError {
                dataSourceStatuses[.contacts] = .needsAccess
            } else {
                dataSourceStatuses[.contacts] = .unavailable(reason: "Fehler")
            }
        }
        
        let messageAccess = await messageService.checkAccess()
        dataSourceStatuses[.imessage] = messageAccess ? .connected : .needsAccess
        AppLogger.log("iMessage access: \(messageAccess)")
        
        let whatsAppAccess = await whatsAppService.checkAccess()
        dataSourceStatuses[.whatsapp] = whatsAppAccess ? .connected : .unavailable(reason: "Nicht installiert")
        
        let callAccess = await callHistoryService.checkAccess()
        dataSourceStatuses[.phone] = callAccess ? .connected : .needsAccess
        dataSourceStatuses[.facetime] = callAccess ? .connected : .needsAccess
        AppLogger.log("CallHistory access: \(callAccess)")
        
        let mailAccess = await mailService.checkAccess()
        dataSourceStatuses[.email] = mailAccess ? .connected : .needsAccess
        AppLogger.log("Mail access: \(mailAccess)")
        AppLogger.log("Bundle: \(Bundle.main.bundleIdentifier ?? "nil"), Path: \(Bundle.main.bundlePath)")
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
        
        // 2a. Bereinigung: ALLE Events mit Datum in der Zukunft löschen
        //     Verhindert fehlerhafte "letzter Kontakt" Anzeige
        do {
            let now = Date()
            let allEvents = try modelContext.fetch(FetchDescriptor<CommunicationEvent>())
            let badEvents = allEvents.filter { $0.date > now }
            if !badEvents.isEmpty {
                AppLogger.contactOperation("Bereinigung (Datum in der Zukunft)", count: badEvents.count)
                for event in badEvents {
                    modelContext.delete(event)
                }
            }
        } catch { }
        
        // 3. Existierende sourceIdentifiers laden für Deduplizierung
        let existingIds: Set<String>
        do {
            let events = try modelContext.fetch(FetchDescriptor<CommunicationEvent>())
            existingIds = Set(events.compactMap(\.sourceIdentifier))
        } catch {
            existingIds = []
        }
        
        // 4. Letztes Kontaktdatum pro Kontakt tracken
        var latestDates: [UUID: Date] = [:]
        for contact in trackedContacts {
            if let date = contact.lastContactDate {
                latestDates[contact.id] = date
            }
        }
        
        // 5. Events aus allen Quellen importieren
        
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
        
        // --- E-Mail ---
        do {
            let emails = try await withTimeout(seconds: 15) {
                try await self.mailService.fetchRecentEmails()
            }
            var count = 0
            
            for email in emails {
                let sourceId = "mail-\(email.messageId)"
                guard !existingIds.contains(sourceId) else { continue }
                
                // Matching: Absender oder Empfänger gegen Kontakte prüfen
                let allAddresses = [email.senderAddress] + email.recipientAddresses
                var matchedContact: TrackedContact?
                for addr in allAddresses {
                    if let c = matchContact(email: addr, lookups: lookups) {
                        matchedContact = c
                        break
                    }
                }
                guard let contact = matchedContact else { continue }
                
                let event = CommunicationEvent(
                    channel: .email,
                    direction: email.isOutgoing ? .outgoing : .incoming,
                    date: email.date,
                    isAutoDetected: true,
                    sourceIdentifier: sourceId
                )
                event.contact = contact
                modelContext.insert(event)
                count += 1
                updateLatestDate(&latestDates, contactId: contact.id, date: email.date)
            }
            
            lastSyncResults[.email] = count
            dataSourceStatuses[.email] = .connected
            AppLogger.syncCompleted(source: .email, itemCount: count)
        } catch {
            handleSyncError(.email, error)
        }
        
        // --- Kalender (Treffen mit Teilnehmern) ---
        do {
            let events = try await withTimeout(seconds: 15) {
                try await self.calendarService.fetchMeetingEvents()
            }
            var count = 0
            
            for calEvent in events {
                // Nur vergangene Kalender-Events zählen als "Kontakt"
                guard calEvent.startDate <= Date() else { continue }
                let sourceId = "cal-\(calEvent.identifier)"
                guard !existingIds.contains(sourceId) else { continue }
                
                // Jeden Teilnehmer matchen
                for attendeeEmail in calEvent.attendees {
                    guard let contact = matchContact(email: attendeeEmail, lookups: lookups) else { continue }
                    
                    let event = CommunicationEvent(
                        channel: .calendar,
                        direction: .mutual,
                        date: calEvent.startDate,
                        summary: calEvent.title,
                        isAutoDetected: true,
                        sourceIdentifier: "\(sourceId)-\(attendeeEmail)"
                    )
                    event.contact = contact
                    modelContext.insert(event)
                    count += 1
                    updateLatestDate(&latestDates, contactId: contact.id, date: calEvent.startDate)
                }
            }
            
            lastSyncResults[.calendar] = count
            dataSourceStatuses[.calendar] = .connected
            AppLogger.syncCompleted(source: .calendar, itemCount: count)
        } catch {
            handleSyncError(.calendar, error)
        }
        
        // 6. lastContactDate aus ALLEN Events berechnen (nicht nur neu importierte)
        for contact in trackedContacts {
            let latestEvent = contact.communicationEvents
                .filter { $0.date <= Date() }  // Nur Events in der Vergangenheit
                .max(by: { $0.date < $1.date })
            if let latestDate = latestEvent?.date {
                if contact.lastContactDate == nil || latestDate > contact.lastContactDate! {
                    contact.lastContactDate = latestDate
                }
            }
        }
        
        // 7. Speichern
        try? modelContext.save()
        
        lastSyncDate = Date()
        isSyncing = false
    }
    
    // MARK: - Helpers
    
    private func updateLatestDate(_ dates: inout [UUID: Date], contactId: UUID, date: Date) {
        // Niemals zukünftige Daten als "letzten Kontakt" speichern
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
            let first = try await group.next()!
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
