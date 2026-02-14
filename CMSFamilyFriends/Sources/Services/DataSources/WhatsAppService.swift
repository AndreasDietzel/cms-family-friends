import Foundation
import SQLite3

/// Service für WhatsApp Nachrichten-Zugriff
/// Liest die WhatsApp SQLite-DB direkt aus
/// Erfordert Full Disk Access
actor WhatsAppService {
    
    /// Metadaten-Struct – bewusst KEIN Nachrichtentext (Datenschutz / Privacy by Design)
    struct WhatsAppMessage {
        let messageId: Int64
        let date: Date
        let isFromMe: Bool
        let contactName: String?
        let contactNumber: String?
        let chatName: String?
    }
    
    /// Pfad zur WhatsApp Datenbank
    private var whatsAppDBPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            // WhatsApp Desktop (Standard)
            "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite",
            // WhatsApp Business
            "\(home)/Library/Group Containers/group.net.whatsapp.WhatsAppSMB.shared/ChatStorage.sqlite",
            // Alternative Pfade
            "\(home)/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Application Support/ChatStorage.sqlite"
        ]
        
        return possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    /// Prüft ob WhatsApp DB gefunden werden kann
    func checkAccess() -> Bool {
        whatsAppDBPath != nil
    }
    
    /// Letzte Nachrichten abrufen
    func fetchRecentMessages(daysPast: Int = 90) async throws -> [WhatsAppMessage] {
        guard let dbPath = whatsAppDBPath else {
            throw ServiceError.notAvailable(
                "WhatsApp Datenbank nicht gefunden. Ist WhatsApp Desktop installiert?"
            )
        }
        
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            throw ServiceError.notAuthorized(
                "Kein Zugriff auf WhatsApp DB. Bitte Full Disk Access aktivieren."
            )
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ServiceError.databaseError("Konnte WhatsApp DB nicht öffnen")
        }
        defer { sqlite3_close(db) }
        
        // WhatsApp verwendet Unix-Timestamps
        let cutoffTimestamp = Int64(Date().timeIntervalSince1970) - Int64(daysPast * 86400)
        
        // Privacy by Design: Kein ZTEXT abfragen – nur Metadaten
        // ZMESSAGETYPE: 0 = Text, 2 = Bild, 3 = Video, 5 = Standort, 8 = Anruf, etc.
        // Nur Text (0) und Anrufe (8) auswerten – keine Medien/Bilder
        let query = """
            SELECT ZWAMESSAGE.Z_PK, ZWAMESSAGE.ZMESSAGEDATE,
                   ZWAMESSAGE.ZISFROMME, ZWACHATSESSION.ZCONTACTJID,
                   ZWACHATSESSION.ZPARTNERNAME
            FROM ZWAMESSAGE
            LEFT JOIN ZWACHATSESSION ON ZWAMESSAGE.ZCHATSESSION = ZWACHATSESSION.Z_PK
            WHERE ZWAMESSAGE.ZMESSAGEDATE > ?
              AND ZWAMESSAGE.ZMESSAGETYPE IN (0, 8)
            ORDER BY ZWAMESSAGE.ZMESSAGEDATE DESC
            LIMIT 5000
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            // Fallback: vielleicht anderes Schema
            throw ServiceError.databaseError(
                "WhatsApp DB Schema nicht erkannt. Möglicherweise hat sich das Format geändert."
            )
        }
        defer { sqlite3_finalize(statement) }
        
        // WhatsApp macOS verwendet Cocoa Date Reference (2001-01-01)
        let cocoaOffset: Double = 978307200
        sqlite3_bind_double(statement, 1, Double(cutoffTimestamp) - cocoaOffset)
        
        var messages: [WhatsAppMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let messageId = sqlite3_column_int64(statement, 0)
            let dateValue = sqlite3_column_double(statement, 1)
            let isFromMe = sqlite3_column_int(statement, 2) == 1
            let contactJid = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let partnerName = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            
            let date = Date(timeIntervalSinceReferenceDate: dateValue)
            
            // Telefonnummer aus JID extrahieren (format: 49123456789@s.whatsapp.net)
            let phoneNumber = contactJid?.components(separatedBy: "@").first.map { "+\($0)" }
            
            messages.append(WhatsAppMessage(
                messageId: messageId,
                date: date,
                isFromMe: isFromMe,
                contactName: partnerName,
                contactNumber: phoneNumber,
                chatName: partnerName
            ))
        }
        
        return messages
    }
}
