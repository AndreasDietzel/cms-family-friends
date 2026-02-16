import Foundation
import os.log

/// Zentrales Logging-System (ISO 25010: Wartbarkeit)
/// Verwendet Apple's os.log für performantes, datenschutzkonformes Logging
enum AppLogger {
    // MARK: - Logger-Instanzen
    private static let syncLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CMSFamilyFriends", category: "Sync")
    private static let dataLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CMSFamilyFriends", category: "Data")
    private static let uiLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CMSFamilyFriends", category: "UI")
    private static let securityLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CMSFamilyFriends", category: "Security")
    
    // MARK: - Sync Events
    
    /// Generisches Info-Log
    static func log(_ message: String) {
        syncLogger.info("\(message, privacy: .public)")
    }
    
    /// Loggt einen erfolgreichen Sync-Vorgang
    static func syncCompleted(source: DataSource, itemCount: Int) {
        syncLogger.info("Sync abgeschlossen: \(source.displayName, privacy: .public) – \(itemCount) Einträge")
    }
    
    /// Loggt einen Sync-Fehler (keine sensiblen Daten!)
    static func syncFailed(source: DataSource, error: Error) {
        syncLogger.error("Sync fehlgeschlagen: \(source.displayName, privacy: .public) – \(error.localizedDescription, privacy: .public)")
    }
    
    /// Loggt Sync-Start
    static func syncStarted() {
        syncLogger.info("Sync gestartet")
    }
    
    // MARK: - Data Events
    
    /// Loggt Datenbank-Operationen (ohne Inhalte!)
    static func databaseAccess(source: String, success: Bool) {
        if success {
            dataLogger.debug("DB-Zugriff erfolgreich: \(source, privacy: .public)")
        } else {
            dataLogger.warning("DB-Zugriff verweigert: \(source, privacy: .public)")
        }
    }
    
    /// Loggt Kontakt-Operationen (nur Anzahl, keine Namen!)
    static func contactOperation(_ operation: String, count: Int) {
        dataLogger.info("Kontakt-Operation: \(operation, privacy: .public) – \(count) Einträge")
    }
    
    // MARK: - Security Events
    
    /// Loggt Berechtigungsanfragen
    static func permissionRequested(for resource: String, granted: Bool) {
        securityLogger.info("Berechtigung angefragt: \(resource, privacy: .public) – \(granted ? "gewährt" : "verweigert", privacy: .public)")
    }
    
    /// Loggt Zugriffsfehler
    static func accessDenied(resource: String) {
        securityLogger.warning("Zugriff verweigert: \(resource, privacy: .public)")
    }
    
    // MARK: - UI Events
    
    /// Loggt Navigation
    static func navigation(to view: String) {
        uiLogger.debug("Navigation: \(view, privacy: .public)")
    }
}
