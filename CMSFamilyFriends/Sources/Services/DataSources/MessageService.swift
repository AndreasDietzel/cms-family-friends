import Foundation
import SQLite3

/// Service für iMessage-Zugriff (liest chat.db direkt)
/// Erfordert Full Disk Access in Systemeinstellungen
actor MessageService {
    
    /// Metadaten-Struct – bewusst KEIN Nachrichtentext (Datenschutz / Privacy by Design)
    struct MessageInfo {
        let rowId: Int64
        let date: Date
        let isFromMe: Bool
        let handleId: String  // Telefonnummer oder E-Mail
        let chatName: String?
    }
    
    /// Pfad zur iMessage Datenbank
    private var chatDBPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Messages/chat.db"
    }
    
    /// Prüft ob Zugriff auf chat.db möglich ist (versucht die DB tatsächlich zu öffnen)
    func checkAccess() -> Bool {
        let path = chatDBPath
        guard FileManager.default.fileExists(atPath: path) else { return false }
        
        // Tatsächlichen SQLite-Zugriff testen (FileManager.isReadableFile ist bei TCC unzuverlässig)
        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        return result == SQLITE_OK
    }
    
    /// Letzte Nachrichten abrufen
    func fetchRecentMessages(daysPast: Int = 90) async throws -> [MessageInfo] {
        guard checkAccess() else {
            throw ServiceError.notAuthorized(
                "Kein Zugriff auf iMessage DB. Bitte Full Disk Access in Systemeinstellungen > Datenschutz aktivieren."
            )
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(chatDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("Konnte iMessage DB nicht öffnen")
        }
        defer { sqlite3_close(db) }
        
        // macOS Cocoa Timestamp Offset (2001-01-01 vs Unix 1970-01-01)
        let cocoaOffset: Int64 = 978307200
        let cutoffTimestamp = Int64(Date().timeIntervalSince1970 - Double(daysPast * 86400) - Double(cocoaOffset)) * 1_000_000_000
        
        // Privacy by Design: Kein Nachrichtentext (m.text) abfragen – nur Metadaten
        let query = """
            SELECT m.ROWID, m.date, m.is_from_me, h.id, c.display_name
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.date > ?
            ORDER BY m.date DESC
            LIMIT 5000
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, cutoffTimestamp)
        
        var messages: [MessageInfo] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(statement, 0)
            let dateNano = sqlite3_column_int64(statement, 1)
            let isFromMe = sqlite3_column_int(statement, 2) == 1
            let handleId = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let chatName = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            
            let date = Date(timeIntervalSince1970: Double(dateNano) / 1_000_000_000 + Double(cocoaOffset))
            
            messages.append(MessageInfo(
                rowId: rowId,
                date: date,
                isFromMe: isFromMe,
                handleId: handleId,
                chatName: chatName
            ))
        }
        
        return messages
    }
    
    /// Nachrichten pro Kontakt-Handle gruppieren
    func fetchMessageCountsByHandle(daysPast: Int = 90) async throws -> [String: Int] {
        let messages = try await fetchRecentMessages(daysPast: daysPast)
        var counts: [String: Int] = [:]
        for msg in messages {
            counts[msg.handleId, default: 0] += 1
        }
        return counts
    }
}
