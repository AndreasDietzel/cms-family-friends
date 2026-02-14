import Foundation
import EventKit
import Combine

/// Manager für Erinnerungen (Apple Reminders Integration)
@MainActor
class ReminderManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var reminderListExists = false
    
    private let eventStore = EKEventStore()
    private let listName = "CMS Family & Friends"
    private var cmsReminderList: EKCalendar?
    
    // MARK: - Authorization
    
    /// Berechtigung für Reminders anfordern
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            isAuthorized = granted
            if granted {
                await setupReminderList()
            }
            return granted
        } catch {
            print("❌ Reminders-Zugriff fehlgeschlagen: \(error)")
            return false
        }
    }
    
    // MARK: - Reminder List Management
    
    /// Eigene Reminders-Liste erstellen oder finden
    private func setupReminderList() async {
        let calendars = eventStore.calendars(for: .reminder)
        
        // Prüfe ob unsere Liste bereits existiert
        if let existing = calendars.first(where: { $0.title == listName }) {
            cmsReminderList = existing
            reminderListExists = true
            return
        }
        
        // Neue Liste erstellen
        let newList = EKCalendar(for: .reminder, eventStore: eventStore)
        newList.title = listName
        newList.source = eventStore.defaultCalendarForNewReminders()?.source
        
        do {
            try eventStore.saveCalendar(newList, commit: true)
            cmsReminderList = newList
            reminderListExists = true
            print("✅ Reminders-Liste '\(listName)' erstellt")
        } catch {
            print("❌ Konnte Reminders-Liste nicht erstellen: \(error)")
        }
    }
    
    // MARK: - Create Reminders
    
    /// Erstellt eine Erinnerung in Apple Reminders
    func createReminder(
        for contact: TrackedContact,
        title: String,
        note: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0
    ) async -> String? {
        guard isAuthorized, let list = cmsReminderList else {
            print("❌ Nicht autorisiert oder keine Liste")
            return nil
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = note
        reminder.calendar = list
        reminder.priority = priority
        
        if let dueDate = dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ Erinnerung erstellt: \(title)")
            return reminder.calendarItemIdentifier
        } catch {
            print("❌ Erinnerung konnte nicht erstellt werden: \(error)")
            return nil
        }
    }
    
    /// Erstellt automatisch eine Kontaktpausen-Erinnerung
    func createContactPauseReminder(for contact: TrackedContact) async -> String? {
        let daysSince = contact.daysSinceLastContact ?? 0
        let title = "\(contact.fullName) kontaktieren"
        let note = "Letzter Kontakt vor \(daysSince) Tagen. Zeit für ein Update!"
        
        let dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        
        let priority: Int
        switch contact.urgencyLevel {
        case 0..<0.75: priority = 0      // Keine
        case 0.75..<1.0: priority = 9    // Niedrig
        case 1.0..<1.5: priority = 5     // Mittel
        default: priority = 1             // Hoch
        }
        
        return await createReminder(
            for: contact,
            title: title,
            note: note,
            dueDate: dueDate,
            priority: priority
        )
    }
    
    /// Erstellt eine Geburtstags-Erinnerung
    func createBirthdayReminder(for contact: TrackedContact) async -> String? {
        guard let birthday = contact.nextBirthday else { return nil }
        
        // 3 Tage vorher erinnern
        let reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: birthday)
        
        let title = "🎂 \(contact.fullName) hat bald Geburtstag!"
        let note = "Geburtstag am \(birthday.formatted(date: .long, time: .omitted))"
        
        return await createReminder(
            for: contact,
            title: title,
            note: note,
            dueDate: reminderDate,
            priority: 5
        )
    }
    
    // MARK: - Complete Reminder
    
    /// Markiert eine Erinnerung als erledigt
    func completeReminder(identifier: String) async -> Bool {
        guard isAuthorized else { return false }
        
        let predicate = eventStore.predicateForReminders(in: cmsReminderList != nil ? [cmsReminderList!] : nil)
        
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self = self,
                      let reminder = reminders?.first(where: { $0.calendarItemIdentifier == identifier }) else {
                    continuation.resume(returning: false)
                    return
                }
                
                reminder.isCompleted = true
                do {
                    try self.eventStore.save(reminder, commit: true)
                    print("✅ Erinnerung abgehakt: \(reminder.title ?? "")")
                    continuation.resume(returning: true)
                } catch {
                    print("❌ Fehler beim Abhaken: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
