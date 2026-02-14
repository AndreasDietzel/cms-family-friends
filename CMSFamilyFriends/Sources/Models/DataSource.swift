import Foundation
import SwiftData

/// Datenquellen-Enum für Sync-Status und Fehlerbehandlung
/// Separiert von CommunicationChannel (fachliche vs. technische Zuordnung)
enum DataSource: String, CaseIterable, Identifiable {
    case calendar = "calendar"
    case contacts = "contacts"
    case imessage = "imessage"
    case whatsapp = "whatsapp"
    case phone = "phone"
    case facetime = "facetime"
    case email = "email"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .calendar: return "Kalender"
        case .contacts: return "Kontakte"
        case .imessage: return "iMessage"
        case .whatsapp: return "WhatsApp"
        case .phone: return "Telefon"
        case .facetime: return "FaceTime"
        case .email: return "E-Mail"
        }
    }
    
    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .contacts: return "person.crop.circle"
        case .imessage: return "message.fill"
        case .whatsapp: return "bubble.left.fill"
        case .phone: return "phone.fill"
        case .facetime: return "video.fill"
        case .email: return "envelope.fill"
        }
    }
    
    /// Ob diese Datenquelle Full Disk Access benötigt
    var requiresFullDiskAccess: Bool {
        switch self {
        case .imessage, .whatsapp, .phone, .facetime, .email: return true
        case .calendar, .contacts: return false
        }
    }
}

/// Status einer Datenquelle
enum DataSourceStatus: Equatable {
    case connected
    case needsAccess
    case unavailable(reason: String)
    case checking
    case disabled
    
    var color: SwiftUI.Color {
        switch self {
        case .connected: return .green
        case .needsAccess: return .orange
        case .unavailable: return .red
        case .checking: return .yellow
        case .disabled: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .connected: return "Verbunden"
        case .needsAccess: return "Zugriff nötig"
        case .unavailable(let reason): return reason
        case .checking: return "Prüfe..."
        case .disabled: return "Deaktiviert"
        }
    }
}

import SwiftUI
