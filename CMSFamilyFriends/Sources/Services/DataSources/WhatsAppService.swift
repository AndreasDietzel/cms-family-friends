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
        // Ausschlüsse:
        //   @broadcast        – status@broadcast (WhatsApp Status-Stories) und Broadcast-Listen
        //   status@%          – alle Status-Container (z.B. status@broadcast explizit)
        //   @newsletter       – WhatsApp Channels (einseitige Abonnements, kein persönlicher Kontakt)
        //   INNER JOIN        – Nachrichten ohne gültige Chat-Session werden nicht importiert
        //   ZMESSAGETYPE IN (...):
        //     6  = System/Gruppen-Ereignis
        //     14 = Ephemeral-Nachricht
        //     15 = Ephemeral-Timer-Änderung
        //     16 = Ephemeral-Vorschau
        //     17 = Gruppen-Einladung
        //     20 = Systembenachrichtigung
        //     23 = Status-Ablauf-Benachrichtigung
        //     26 = Status-/Story-Benachrichtigung (gesehener Status)
        let query = """
            SELECT ZWAMESSAGE.Z_PK, ZWAMESSAGE.ZMESSAGEDATE,
                   ZWAMESSAGE.ZISFROMME, ZWACHATSESSION.ZCONTACTJID,
                   ZWACHATSESSION.ZPARTNERNAME
            FROM ZWAMESSAGE
            INNER JOIN ZWACHATSESSION ON ZWAMESSAGE.ZCHATSESSION = ZWACHATSESSION.Z_PK
            WHERE ZWAMESSAGE.ZMESSAGEDATE > ?
              AND ZWACHATSESSION.ZCONTACTJID NOT LIKE '%@broadcast'
              AND ZWACHATSESSION.ZCONTACTJID NOT LIKE 'status@%'
              AND ZWACHATSESSION.ZCONTACTJID NOT LIKE '%@newsletter'
              AND ZWAMESSAGE.ZMESSAGETYPE NOT IN (6, 14, 15, 16, 17, 20, 23, 26)
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
        
        // WhatsApp macOS: Timestamp-Format erkennen (Unix vs Cocoa Reference Date)
        // Cocoa Reference Date = Sekunden seit 2001-01-01 (typisch < 1 Mrd. für aktuelle Daten)
        // Unix Timestamp = Sekunden seit 1970-01-01 (typisch > 1,5 Mrd. für aktuelle Daten)
        let cocoaOffset: Double = 978307200
        
        // Cutoff für beide Formate binden – der niedrigere Wert matcht in beiden Fällen
        sqlite3_bind_double(statement, 1, Double(cutoffTimestamp) - cocoaOffset)
        
        var messages: [WhatsAppMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let messageId = sqlite3_column_int64(statement, 0)
            let dateValue = sqlite3_column_double(statement, 1)
            let isFromMe = sqlite3_column_int(statement, 2) == 1
            let contactJid = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let partnerName = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            
            // Auto-Detect: Werte > 1 Mrd. sind Unix-Timestamps, kleinere sind Cocoa Reference Dates
            let date: Date
            if dateValue > 1_000_000_000 {
                date = Date(timeIntervalSince1970: dateValue)
            } else {
                date = Date(timeIntervalSinceReferenceDate: dateValue)
            }
            
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
