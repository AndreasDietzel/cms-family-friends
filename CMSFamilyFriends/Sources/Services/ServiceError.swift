import Foundation

/// Fehlertypen für Services (ISO 25010: Zuverlässigkeit)
/// Erweitert um Rate-Limiting, Schema-Versionierung und Datenexport
enum ServiceError: LocalizedError {
    case notAuthorized(String)
    case notAvailable(String)
    case databaseError(String)
    case parseError(String)
    case schemaVersionMismatch(expected: String, found: String)
    case rateLimited(String)
    case exportError(String)
    case importError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized(let msg): return "Nicht autorisiert: \(msg)"
        case .notAvailable(let msg): return "Nicht verfügbar: \(msg)"
        case .databaseError(let msg): return "Datenbankfehler: \(msg)"
        case .parseError(let msg): return "Parse-Fehler: \(msg)"
        case .schemaVersionMismatch(let expected, let found):
            return "DB-Schema inkompatibel (erwartet: \(expected), gefunden: \(found))"
        case .rateLimited(let msg): return "Rate-Limit: \(msg)"
        case .exportError(let msg): return "Export-Fehler: \(msg)"
        case .importError(let msg): return "Import-Fehler: \(msg)"
        }
    }
    
    /// Benutzerfreundliche Handlungsempfehlung
    var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "Bitte überprüfe die Berechtigungen in Systemeinstellungen > Datenschutz & Sicherheit."
        case .notAvailable:
            return "Die Datenquelle ist aktuell nicht verfügbar. Prüfe ob die zugehörige App installiert ist."
        case .databaseError, .schemaVersionMismatch:
            return "Möglicherweise hat sich das Datenbankformat durch ein macOS-Update geändert. Prüfe auf ein App-Update."
        case .rateLimited:
            return "Bitte warte einen Moment, bevor du erneut synchronisierst."
        default:
            return nil
        }
    }
}
