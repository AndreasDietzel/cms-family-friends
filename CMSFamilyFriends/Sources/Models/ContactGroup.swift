import Foundation
import SwiftData

/// Kontaktgruppe mit individuellem Kontakt-Intervall
@Model
final class ContactGroup {
    var id: UUID
    var name: String
    var icon: String  // SF Symbol Name
    var colorHex: String
    
    /// Gewünschtes Kontakt-Intervall in Tagen
    var contactIntervalDays: Int
    
    /// Warnungs-Schwelle in Tagen (wann wird gewarnt, bevor überfällig)
    var warningThresholdDays: Int
    
    /// Zugehörige Kontakte
    var contacts: [TrackedContact]
    
    /// Priorität (höher = wichtiger)
    var priority: Int
    
    /// Erstellt am
    var createdAt: Date
    
    /// Anzahl überfälliger Kontakte
    var overdueCount: Int {
        contacts.filter(\.isOverdue).count
    }
    
    init(
        name: String,
        icon: String = "person.2",
        colorHex: String = "#007AFF",
        contactIntervalDays: Int,
        warningThresholdDays: Int? = nil,
        priority: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.contactIntervalDays = contactIntervalDays
        self.warningThresholdDays = warningThresholdDays ?? max(1, contactIntervalDays / 4)
        self.contacts = []
        self.priority = priority
        self.createdAt = Date()
    }
    
    /// Vordefinierte Standard-Gruppen
    static let defaultGroups: [(name: String, icon: String, color: String, interval: Int, priority: Int)] = [
        ("Familie", "house.fill", "#FF3B30", 7, 100),
        ("Enge Freunde", "heart.fill", "#FF9500", 14, 80),
        ("Freunde", "person.2.fill", "#007AFF", 30, 60),
        ("Bekannte", "person.fill", "#34C759", 90, 40),
        ("Beruflich", "briefcase.fill", "#5856D6", 60, 50),
    ]
}
