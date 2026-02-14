import Foundation
import SwiftData

/// Ein einzelnes Kommunikationsereignis
@Model
final class CommunicationEvent {
    var id: UUID
    
    /// Art der Kommunikation
    var channelRawValue: String
    var channel: CommunicationChannel {
        get { CommunicationChannel(rawValue: channelRawValue) ?? .unknown }
        set { channelRawValue = newValue.rawValue }
    }
    
    /// Richtung der Kommunikation
    var directionRawValue: String
    var direction: CommunicationDirection {
        get { CommunicationDirection(rawValue: directionRawValue) ?? .unknown }
        set { directionRawValue = newValue.rawValue }
    }
    
    /// Zeitpunkt
    var date: Date
    
    /// Dauer (für Anrufe/FaceTime) in Sekunden
    var durationSeconds: Int?
    
    /// Kurze Beschreibung/Betreff
    var summary: String?
    
    /// Zugehöriger Kontakt
    @Relationship
    var contact: TrackedContact?
    
    /// Automatisch erkannt oder manuell eingetragen
    var isAutoDetected: Bool
    
    /// Quell-Identifier (z.B. EventKit ID, Message ID)
    var sourceIdentifier: String?
    
    init(
        channel: CommunicationChannel,
        direction: CommunicationDirection,
        date: Date,
        durationSeconds: Int? = nil,
        summary: String? = nil,
        isAutoDetected: Bool = true,
        sourceIdentifier: String? = nil
    ) {
        self.id = UUID()
        self.channelRawValue = channel.rawValue
        self.directionRawValue = direction.rawValue
        self.date = date
        self.durationSeconds = durationSeconds
        self.summary = summary
        self.isAutoDetected = isAutoDetected
        self.sourceIdentifier = sourceIdentifier
    }
}

/// Kommunikationskanäle
enum CommunicationChannel: String, CaseIterable, Codable {
    case phone = "phone"
    case facetime = "facetime"
    case imessage = "imessage"
    case whatsapp = "whatsapp"
    case email = "email"
    case calendar = "calendar"      // Persönliches Treffen (Kalender-Event)
    case manual = "manual"          // Manueller Eintrag
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .phone: return "Telefon"
        case .facetime: return "FaceTime"
        case .imessage: return "iMessage"
        case .whatsapp: return "WhatsApp"
        case .email: return "E-Mail"
        case .calendar: return "Treffen"
        case .manual: return "Manuell"
        case .unknown: return "Unbekannt"
        }
    }
    
    var icon: String {
        switch self {
        case .phone: return "phone.fill"
        case .facetime: return "video.fill"
        case .imessage: return "message.fill"
        case .whatsapp: return "bubble.left.fill"
        case .email: return "envelope.fill"
        case .calendar: return "calendar"
        case .manual: return "pencil"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Richtung der Kommunikation
enum CommunicationDirection: String, CaseIterable, Codable {
    case incoming = "incoming"
    case outgoing = "outgoing"
    case mutual = "mutual"    // z.B. Treffen
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .incoming: return "Eingehend"
        case .outgoing: return "Ausgehend"
        case .mutual: return "Gegenseitig"
        case .unknown: return "Unbekannt"
        }
    }
}
