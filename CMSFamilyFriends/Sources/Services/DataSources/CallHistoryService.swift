import Foundation
import SQLite3

/// Service für Telefon-Anrufhistorie
/// Liest die CallHistory.storedata auf macOS
actor CallHistoryService {
    
    struct CallRecord {
        let identifier: String
        let phoneNumber: String
        let date: Date
        let duration: TimeInterval
        let isOutgoing: Bool
        let isAnswered: Bool
    }
    
    /// Pfad zur Call History DB
    private var callHistoryDBPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/CallHistoryDB/CallHistory.storedata"
    }
    
    /// Prüft ob Zugriff möglich ist
    func checkAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: callHistoryDBPath)
    }
    
    /// Letzte Anrufe abrufen
    func fetchRecentCalls(daysPast: Int = 90) async throws -> [CallRecord] {
        guard checkAccess() else {
            throw ServiceError.notAuthorized(
                "Kein Zugriff auf Anrufhistorie. Bitte Full Disk Access aktivieren."
            )
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(callHistoryDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("Konnte CallHistory DB nicht öffnen")
        }
        defer { sqlite3_close(db) }
        
        let cocoaOffset: Double = 978307200
        let cutoffDate = Date().timeIntervalSince1970 - Double(daysPast * 86400) - cocoaOffset
        
        let query = """
            SELECT ZUNIQUE_ID, ZADDRESS, ZDATE, ZDURATION, ZORIGINATED, ZANSWERED
            FROM ZCALLRECORD
            WHERE ZDATE > ?
            ORDER BY ZDATE DESC
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_double(statement, 1, cutoffDate)
        
        var calls: [CallRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let uniqueId = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? UUID().uuidString
            let address = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let dateValue = sqlite3_column_double(statement, 2)
            let duration = sqlite3_column_double(statement, 3)
            let originated = sqlite3_column_int(statement, 4) == 1
            let answered = sqlite3_column_int(statement, 5) == 1
            
            let date = Date(timeIntervalSinceReferenceDate: dateValue)
            
            calls.append(CallRecord(
                identifier: uniqueId,
                phoneNumber: address,
                date: date,
                duration: duration,
                isOutgoing: originated,
                isAnswered: answered
            ))
        }
        
        return calls
    }
}
