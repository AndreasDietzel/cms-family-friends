import Foundation

/// Fehlertypen für Services
enum ServiceError: LocalizedError {
    case notAuthorized(String)
    case notAvailable(String)
    case databaseError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized(let msg): return "Nicht autorisiert: \(msg)"
        case .notAvailable(let msg): return "Nicht verfügbar: \(msg)"
        case .databaseError(let msg): return "Datenbankfehler: \(msg)"
        case .parseError(let msg): return "Parse-Fehler: \(msg)"
        }
    }
}
