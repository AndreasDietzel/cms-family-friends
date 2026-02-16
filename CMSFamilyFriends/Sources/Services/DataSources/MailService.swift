import Foundation
import SQLite3

/// Service für Mail.app E-Mail-Tracking
/// Liest die Mail-Datenbank direkt aus
/// Privacy by Design: Kein Betreff/Body – nur Metadaten (Absender, Empfänger, Datum, Richtung)
actor MailService {
    
    struct EmailRecord {
        let messageId: String
        let senderAddress: String
        let recipientAddresses: [String]
        let date: Date
        let isOutgoing: Bool
    }
    
    /// Eigene E-Mail-Adressen (für isOutgoing-Erkennung)
    private var userEmailAddresses: Set<String> = []
    
    /// Pfad zur Mail-Datenbank
    private var mailDBPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let mailDir = "\(home)/Library/Mail"
        
        let possiblePaths = [
            "\(mailDir)/V10/MailData/Envelope Index",
            "\(mailDir)/V9/MailData/Envelope Index",
            "\(mailDir)/V8/MailData/Envelope Index"
        ]
        
        return possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Prüft ob Zugriff möglich ist (versucht die DB tatsächlich zu öffnen)
    func checkAccess() -> Bool {
        guard let path = mailDBPath else { return false }
        
        // Tatsächlichen SQLite-Zugriff testen
        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        return result == SQLITE_OK
    }
    
    /// Eigene E-Mail-Adressen aus Mail-Accounts laden
    private func loadUserEmailAddresses(db: OpaquePointer?) {
        // Versuche eigene Adressen aus der Datenbank zu laden
        let query = "SELECT DISTINCT address FROM addresses WHERE comment = 'sender' LIMIT 10"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let addr = sqlite3_column_text(statement, 0) {
                userEmailAddresses.insert(String(cString: addr).lowercased())
            }
        }
    }
    
    /// Empfänger-Adressen für eine Nachricht abrufen
    private func fetchRecipients(db: OpaquePointer?, messageRowId: Int64) -> [String] {
        let query = """
            SELECT a.address FROM addresses a
            JOIN recipients r ON a.ROWID = r.address_id
            WHERE r.message_id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, messageRowId)
        
        var addresses: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let addr = sqlite3_column_text(statement, 0) {
                addresses.append(String(cString: addr))
            }
        }
        return addresses
    }
    
    /// Letzte E-Mails abrufen
    func fetchRecentEmails(daysPast: Int = 90) async throws -> [EmailRecord] {
        guard let dbPath = mailDBPath else {
            throw ServiceError.notAvailable("Mail-Datenbank nicht gefunden")
        }
        
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            throw ServiceError.notAuthorized(
                "Kein Zugriff auf Mail-Datenbank. Bitte Full Disk Access aktivieren."
            )
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("Konnte Mail DB nicht öffnen")
        }
        defer { sqlite3_close(db) }
        
        // Eigene Adressen laden für isOutgoing-Erkennung
        loadUserEmailAddresses(db: db)
        
        // Mail.app speichert Timestamps als Unix-Timestamps (seit 1970)
        let cutoffDate = Date().timeIntervalSince1970 - Double(daysPast * 86400)
        
        // Privacy by Design: Kein subject/body – nur Metadaten
        let query = """
            SELECT m.ROWID, m.message_id, a.address, m.date_sent
            FROM messages m
            LEFT JOIN addresses a ON m.sender = a.ROWID
            WHERE m.date_sent > ?
            ORDER BY m.date_sent DESC
            LIMIT 5000
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("Mail DB Schema nicht kompatibel")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_double(statement, 1, cutoffDate)
        
        var emails: [EmailRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(statement, 0)
            let messageId = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? UUID().uuidString
            let sender = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let dateSent = sqlite3_column_double(statement, 3)
            
            // Mail.app speichert date_sent als Unix-Timestamp (seit 1970)
            let date = Date(timeIntervalSince1970: dateSent)
            let recipients = fetchRecipients(db: db, messageRowId: rowId)
            let isOutgoing = userEmailAddresses.contains(sender.lowercased())
            
            emails.append(EmailRecord(
                messageId: messageId,
                senderAddress: sender,
                recipientAddresses: recipients,
                date: date,
                isOutgoing: isOutgoing
            ))
        }
        
        return emails
    }
}
