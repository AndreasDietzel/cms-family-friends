import Foundation
import SQLite3

/// Service für Mail.app E-Mail-Tracking
/// Liest die Mail-Datenbank direkt aus
actor MailService {
    
    struct EmailRecord {
        let messageId: String
        let subject: String?
        let senderAddress: String
        let recipientAddresses: [String]
        let date: Date
        let isOutgoing: Bool
    }
    
    /// Pfad zur Mail-Datenbank
    private var mailDBPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let mailDir = "\(home)/Library/Mail"
        
        // Mail.app verwendet eine Envelope-Index Datenbank
        let possiblePaths = [
            "\(mailDir)/V10/MailData/Envelope Index",
            "\(mailDir)/V9/MailData/Envelope Index",
            "\(mailDir)/V8/MailData/Envelope Index"
        ]
        
        return possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Prüft ob Zugriff möglich ist
    func checkAccess() -> Bool {
        mailDBPath != nil
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
        
        let cocoaOffset: Double = 978307200
        let cutoffDate = Date().timeIntervalSince1970 - Double(daysPast * 86400) - cocoaOffset
        
        let query = """
            SELECT m.message_id, m.subject, a.address, m.date_sent
            FROM messages m
            LEFT JOIN addresses a ON m.sender = a.ROWID
            WHERE m.date_sent > ?
            ORDER BY m.date_sent DESC
            LIMIT 5000
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            // Mail DB Schema kann variieren
            throw ServiceError.databaseError("Mail DB Schema nicht kompatibel")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_double(statement, 1, cutoffDate)
        
        var emails: [EmailRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let messageId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? UUID().uuidString
            let subject = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let sender = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let dateSent = sqlite3_column_double(statement, 3)
            
            let date = Date(timeIntervalSinceReferenceDate: dateSent)
            
            emails.append(EmailRecord(
                messageId: messageId,
                subject: subject,
                senderAddress: sender,
                recipientAddresses: [], // TODO: Empfänger aus separater Tabelle
                date: date,
                isOutgoing: false  // TODO: Prüfen anhand der eigenen E-Mail-Adressen
            ))
        }
        
        return emails
    }
}
