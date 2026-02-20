import Foundation
import SwiftData

/// Ein getrackter Kontakt mit allen Kommunikationsmetadaten
@Model
final class TrackedContact {
    var id: UUID
    var firstName: String
    var lastName: String
    var nickname: String?
    
    /// Apple Contacts ID für die Verknüpfung
    var appleContactIdentifier: String?
    
    /// Geburtstag
    var birthday: Date?
    
    /// Kontaktgruppe (z.B. Familie, enge Freunde, Bekannte)
    @Relationship(inverse: \ContactGroup.contacts)
    var group: ContactGroup?
    
    /// Alle Kommunikationsereignisse
    @Relationship(deleteRule: .cascade)
    var communicationEvents: [CommunicationEvent]
    
    /// Aktive Erinnerungen
    @Relationship(deleteRule: .cascade)
    var reminders: [ContactReminder]
    
    /// Profilbild-Daten (optional)
    var profileImageData: Data?
    
    /// Datum des letzten Kontakts (berechnet)
    var lastContactDate: Date?
    
    /// Notizen
    var notes: String?
    
    /// Erstellt am
    var createdAt: Date
    
    /// Aktiv/Inaktiv
    var isActive: Bool
    
    /// Individueller Kontakt-Zyklus in Tagen (überschreibt Gruppen-Zyklus wenn gesetzt)
    var customContactIntervalDays: Int?
    
    /// Effektives Intervall: Kontakt-Zyklus > Gruppen-Zyklus > nil
    var effectiveIntervalDays: Int? {
        customContactIntervalDays ?? group?.contactIntervalDays
    }
    
    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
    
    /// Tage seit letztem Kontakt
    var daysSinceLastContact: Int? {
        guard let lastContact = lastContactDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day
    }
    
    /// Ist der Kontakt überfällig basierend auf effektivem Intervall?
    var isOverdue: Bool {
        guard let days = daysSinceLastContact,
              let interval = effectiveIntervalDays else { return false }
        return days > interval
    }
    
    /// Dringlichkeitslevel (0.0 - 1.0+)
    var urgencyLevel: Double {
        guard let days = daysSinceLastContact,
              let interval = effectiveIntervalDays,
              interval > 0 else { return 0 }
        return Double(days) / Double(interval)
    }
    
    /// Nächster Geburtstag
    var nextBirthday: Date? {
        guard let birthday = birthday else { return nil }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        var components = calendar.dateComponents([.month, .day], from: birthday)
        components.year = calendar.component(.year, from: todayStart)
        
        guard let thisYearBirthday = calendar.date(from: components) else { return nil }
        
        if thisYearBirthday >= todayStart {
            return thisYearBirthday
        } else {
            components.year = calendar.component(.year, from: todayStart) + 1
            return calendar.date(from: components)
        }
    }
    
    /// Tage bis zum nächsten Geburtstag
    var daysUntilBirthday: Int? {
        guard let next = nextBirthday else { return nil }
        let todayStart = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: todayStart, to: next).day
    }
    
    init(
        firstName: String,
        lastName: String,
        nickname: String? = nil,
        appleContactIdentifier: String? = nil,
        birthday: Date? = nil
    ) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.appleContactIdentifier = appleContactIdentifier
        self.birthday = birthday
        self.communicationEvents = []
        self.reminders = []
        self.createdAt = Date()
        self.isActive = true
    }
}
