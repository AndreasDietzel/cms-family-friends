import Foundation
import SwiftData

// Sendable – wird als Ergebnis von @ModelActor → @MainActor übertragen
struct SyncResult: Sendable {
    var errors: [SyncError] = []
    var statuses: [DataSource: DataSourceStatus] = [:]
    var counts: [DataSource: Int] = [:]
}

/// Background-Actor für alle SwiftData-Sync-Operationen.
/// Läuft auf eigenem Executor (kein Main Thread) – verhindert UI-Freezes
/// bei Navigation (z.B. Dashboard → Kontakte) während ein Sync läuft.
/// Der eigene ModelContext merged Änderungen automatisch in den Main-Context.
@ModelActor
actor SyncActor {
    private let messageService: MessageService
    private let callHistoryService: CallHistoryService
    private let whatsAppService: WhatsAppService
    private let contactsService: ContactsService

    init(
        modelContainer: ModelContainer,
        messageService: MessageService,
        callHistoryService: CallHistoryService,
        whatsAppService: WhatsAppService,
        contactsService: ContactsService
    ) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultModelExecutor(context: context)
        self.messageService = messageService
        self.callHistoryService = callHistoryService
        self.whatsAppService = whatsAppService
        self.contactsService = contactsService
    }

    // MARK: - Main Sync

    func performSync(syncDaysPast: Int, idCutoffDate: Date) async -> SyncResult {
        var result = SyncResult()

        // Tracked contacts laden
        let trackedContacts: [TrackedContact]
        do {
            trackedContacts = try modelContext.fetch(FetchDescriptor<TrackedContact>())
        } catch {
            return result
        }
        guard !trackedContacts.isEmpty else { return result }

        // One-time Cleanups
        await performWhatsAppStatusCleanupIfNeeded(trackedContacts: trackedContacts)
        await performEmailCalendarCleanupIfNeeded(trackedContacts: trackedContacts)

        // Lookup-Tabelle aufbauen (Phone/Email/Name → TrackedContact)
        let lookups = await buildLookups(trackedContacts: trackedContacts, result: &result)

        // Existierende sourceIdentifiers im Sync-Fenster laden
        var existingIds: Set<String>
        do {
            let descriptor = FetchDescriptor<CommunicationEvent>(
                predicate: #Predicate { $0.date > idCutoffDate }
            )
            let events = try modelContext.fetch(descriptor)
            existingIds = Set(events.compactMap(\.sourceIdentifier))
        } catch {
            existingIds = []
        }

        // Letztes Kontaktdatum pro Kontakt vorhalten
        var latestDates: [UUID: Date] = [:]
        for contact in trackedContacts {
            if let date = contact.lastContactDate {
                latestDates[contact.id] = date
            }
        }

        // --- Telefon & FaceTime ---
        do {
            let calls = try await withTimeout(seconds: 15) {
                try await self.callHistoryService.fetchRecentCalls(daysPast: syncDaysPast)
            }
            var phoneCount = 0
            var faceTimeCount = 0
            for (index, call) in calls.enumerated() {
                if index % 50 == 0 { await Task.yield() }
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
                existingIds.insert(sourceId)
                if call.isFaceTime { faceTimeCount += 1 } else { phoneCount += 1 }
                updateLatestDate(&latestDates, contactId: contact.id, date: call.date)
            }
            result.counts[.phone] = phoneCount
            result.counts[.facetime] = faceTimeCount
            result.statuses[.phone] = .connected
            result.statuses[.facetime] = .connected
            AppLogger.syncCompleted(source: .phone, itemCount: phoneCount)
            AppLogger.syncCompleted(source: .facetime, itemCount: faceTimeCount)
        } catch {
            appendError(&result, source: .phone, error: error)
            appendError(&result, source: .facetime, error: error)
        }

        // --- iMessage ---
        do {
            let messages = try await withTimeout(seconds: 15) {
                try await self.messageService.fetchRecentMessages(daysPast: syncDaysPast)
            }
            var count = 0
            for (index, msg) in messages.enumerated() {
                if index % 50 == 0 { await Task.yield() }
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
                existingIds.insert(sourceId)
                count += 1
                updateLatestDate(&latestDates, contactId: contact.id, date: msg.date)
            }
            result.counts[.imessage] = count
            result.statuses[.imessage] = .connected
            AppLogger.syncCompleted(source: .imessage, itemCount: count)
        } catch {
            appendError(&result, source: .imessage, error: error)
        }

        // --- WhatsApp ---
        do {
            let messages = try await withTimeout(seconds: 15) {
                try await self.whatsAppService.fetchRecentMessages(daysPast: syncDaysPast)
            }
            var count = 0
            for (index, msg) in messages.enumerated() {
                if index % 50 == 0 { await Task.yield() }
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
                existingIds.insert(sourceId)
                count += 1
                updateLatestDate(&latestDates, contactId: contact.id, date: msg.date)
            }
            result.counts[.whatsapp] = count
            result.statuses[.whatsapp] = .connected
            AppLogger.syncCompleted(source: .whatsapp, itemCount: count)
        } catch {
            appendError(&result, source: .whatsapp, error: error)
        }

        // lastContactDate für alle Kontakte aktualisieren
        let now = Date()
        for contact in trackedContacts {
            if let existing = contact.lastContactDate, existing > now {
                contact.lastContactDate = nil
            }
            if let latestDate = latestDates[contact.id], latestDate <= now {
                if let existing = contact.lastContactDate {
                    if latestDate > existing { contact.lastContactDate = latestDate }
                } else {
                    contact.lastContactDate = latestDate
                }
            }
        }

        // Speichern – läuft vollständig off-main-thread
        do {
            try modelContext.save()
        } catch {
            result.errors.append(SyncError(source: .contacts, message: "Fehler beim Speichern: \(error.localizedDescription)"))
            AppLogger.syncFailed(source: .contacts, error: error)
        }

        await performOldEventsPruningIfNeeded()

        return result
    }

    // MARK: - Lookup

    private struct ContactLookupTable {
        var byPhone: [String: TrackedContact] = [:]
        var byEmail: [String: TrackedContact] = [:]
        var byName: [String: TrackedContact] = [:]
    }

    private func normalizePhone(_ number: String) -> String {
        let digits = number.filter(\.isNumber)
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    private func buildLookups(
        trackedContacts: [TrackedContact],
        result: inout SyncResult
    ) async -> ContactLookupTable {
        var lookups = ContactLookupTable()

        for contact in trackedContacts {
            let key = "\(contact.firstName) \(contact.lastName)"
                .lowercased().trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && key != " " {
                lookups.byName[key] = contact
            }
        }

        do {
            let appleContacts = try await contactsService.fetchAllContacts()
            result.statuses[.contacts] = .connected
            result.counts[.contacts] = appleContacts.count
            AppLogger.syncCompleted(source: .contacts, itemCount: appleContacts.count)

            // O(1)-Lookup statt O(n) first(where:) pro tracked-Kontakt
            let appleContactById = Dictionary(uniqueKeysWithValues: appleContacts.map { ($0.identifier, $0) })

            for tracked in trackedContacts {
                guard let appleId = tracked.appleContactIdentifier else { continue }
                guard let apple = appleContactById[appleId] else { continue }
                for phone in apple.phoneNumbers {
                    let normalized = normalizePhone(phone)
                    if !normalized.isEmpty { lookups.byPhone[normalized] = tracked }
                }
                for email in apple.emailAddresses {
                    lookups.byEmail[email.lowercased()] = tracked
                }
            }
        } catch {
            result.errors.append(SyncError(source: .contacts, message: error.localizedDescription))
            if let serviceError = error as? ServiceError {
                switch serviceError {
                case .notAuthorized: result.statuses[.contacts] = .needsAccess
                default: result.statuses[.contacts] = .unavailable(reason: "Fehler")
                }
            }
            AppLogger.syncFailed(source: .contacts, error: error)
        }

        return lookups
    }

    private func matchContact(
        phone: String? = nil,
        email: String? = nil,
        name: String? = nil,
        lookups: ContactLookupTable
    ) -> TrackedContact? {
        if let phone, !phone.isEmpty {
            let normalized = normalizePhone(phone)
            if !normalized.isEmpty, let contact = lookups.byPhone[normalized] { return contact }
        }
        if let email, !email.isEmpty {
            if let contact = lookups.byEmail[email.lowercased()] { return contact }
        }
        if let name, !name.isEmpty {
            if let contact = lookups.byName[name.lowercased()] { return contact }
        }
        return nil
    }

    private func updateLatestDate(_ dates: inout [UUID: Date], contactId: UUID, date: Date) {
        guard date <= Date() else { return }
        if let existing = dates[contactId] {
            if date > existing { dates[contactId] = date }
        } else {
            dates[contactId] = date
        }
    }

    private func appendError(_ result: inout SyncResult, source: DataSource, error: Error) {
        result.errors.append(SyncError(source: source, message: error.localizedDescription))
        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .notAuthorized: result.statuses[source] = .needsAccess
            case .notAvailable(let msg): result.statuses[source] = .unavailable(reason: msg)
            default: result.statuses[source] = .unavailable(reason: "Fehler")
            }
        }
        AppLogger.syncFailed(source: source, error: error)
    }

    // MARK: - Data Cleanup Migrations

    private func performWhatsAppStatusCleanupIfNeeded(trackedContacts: [TrackedContact]) async {
        let flagKey = "whatsappStatusCleanupV3Done"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        do {
            let allWAEvents = try modelContext.fetch(
                FetchDescriptor<CommunicationEvent>(
                    predicate: #Predicate { $0.channelRawValue == "whatsapp" }
                )
            )
            UserDefaults.standard.set(true, forKey: "whatsappStatusCleanupV1Done")
            UserDefaults.standard.set(true, forKey: "whatsappStatusCleanupV2Done")
            guard !allWAEvents.isEmpty else {
                UserDefaults.standard.set(true, forKey: flagKey)
                return
            }
            let affectedContacts = Set(allWAEvents.compactMap(\.contact))
            for event in allWAEvents { modelContext.delete(event) }
            let directChannels: Set<String> = ["phone", "facetime", "imessage", "reallife", "manual"]
            for contact in affectedContacts {
                let remaining = contact.communicationEvents.filter { directChannels.contains($0.channelRawValue) }
                contact.lastContactDate = remaining.map(\.date).filter { $0 <= Date() }.max()
            }
            UserDefaults.standard.set(true, forKey: flagKey)
            AppLogger.contactOperation(
                "WhatsApp V3-Bereinigung: \(allWAEvents.count) Events entfernt",
                count: allWAEvents.count
            )
            try? modelContext.save()
        } catch {
            AppLogger.syncFailed(source: .whatsapp, error: error)
        }
    }

    private func performEmailCalendarCleanupIfNeeded(trackedContacts: [TrackedContact]) async {
        let flagKey = "emailCalendarCleanupV1Done"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
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
            for event in eventsToDelete { modelContext.delete(event) }
            let directChannels: Set<String> = ["phone", "facetime", "imessage", "whatsapp", "reallife", "manual"]
            for contact in affectedContacts {
                let remaining = contact.communicationEvents.filter { directChannels.contains($0.channelRawValue) }
                contact.lastContactDate = remaining.map(\.date).filter { $0 <= Date() }.max()
            }
            UserDefaults.standard.set(true, forKey: flagKey)
            AppLogger.contactOperation(
                "E-Mail/Kalender-Bereinigung: \(eventsToDelete.count) Events entfernt",
                count: eventsToDelete.count
            )
            try? modelContext.save()
        } catch {
            AppLogger.syncFailed(source: .email, error: error)
        }
    }

    private func performOldEventsPruningIfNeeded() async {
        let flagKey = "lastOldEventsPruningDate"
        let lastPruning = UserDefaults.standard.object(forKey: flagKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastPruning) > 86400 else { return }
        do {
            let cutoffDate = Date().addingTimeInterval(-180 * 86400)
            let descriptor = FetchDescriptor<CommunicationEvent>(
                predicate: #Predicate { $0.date < cutoffDate && $0.isAutoDetected == true }
            )
            let oldEvents = try modelContext.fetch(descriptor)
            guard !oldEvents.isEmpty else {
                UserDefaults.standard.set(Date(), forKey: flagKey)
                return
            }
            for event in oldEvents { modelContext.delete(event) }
            try? modelContext.save()
            UserDefaults.standard.set(Date(), forKey: flagKey)
            AppLogger.contactOperation(
                "Alte Events bereinigt: \(oldEvents.count) Events älter als 180 Tage entfernt",
                count: oldEvents.count
            )
        } catch {
            AppLogger.syncFailed(source: .contacts, error: error)
        }
    }

    // MARK: - Timeout Helper

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
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
