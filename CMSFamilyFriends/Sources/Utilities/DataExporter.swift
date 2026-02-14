import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Export/Import-Manager für Datensouveränität (ISO 25010: Portabilität)
/// Exportiert/importiert Kontaktdaten im JSON-Format ohne sensible Systemdaten
@MainActor
class DataExporter {
    
    // MARK: - Export-Modelle (ohne sensible Daten)
    
    struct ExportData: Codable {
        let version: String
        let exportDate: Date
        let contacts: [ExportContact]
        let groups: [ExportGroup]
    }
    
    struct ExportContact: Codable {
        let firstName: String
        let lastName: String
        let nickname: String?
        let birthday: Date?
        let groupName: String?
        let notes: String?
        let isActive: Bool
        // Bewusst KEINE: appleContactIdentifier, profileImageData, communicationEvents
    }
    
    struct ExportGroup: Codable {
        let name: String
        let icon: String
        let colorHex: String
        let contactIntervalDays: Int
        let warningThresholdDays: Int
        let priority: Int
    }
    
    // MARK: - Export
    
    /// Exportiert alle Kontakte und Gruppen als JSON
    static func exportData(contacts: [TrackedContact], groups: [ContactGroup]) throws -> Data {
        let exportContacts = contacts.map { contact in
            ExportContact(
                firstName: contact.firstName,
                lastName: contact.lastName,
                nickname: contact.nickname,
                birthday: contact.birthday,
                groupName: contact.group?.name,
                notes: contact.notes,
                isActive: contact.isActive
            )
        }
        
        let exportGroups = groups.map { group in
            ExportGroup(
                name: group.name,
                icon: group.icon,
                colorHex: group.colorHex,
                contactIntervalDays: group.contactIntervalDays,
                warningThresholdDays: group.warningThresholdDays,
                priority: group.priority
            )
        }
        
        let exportData = ExportData(
            version: "1.0",
            exportDate: Date(),
            contacts: exportContacts,
            groups: exportGroups
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(exportData)
    }
    
    // MARK: - Import
    
    /// Importiert Kontakte und Gruppen aus JSON
    static func importData(from data: Data, into context: ModelContext) throws -> (contacts: Int, groups: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importData = try decoder.decode(ExportData.self, from: data)
        
        // Gruppen importieren (nur wenn nicht bereits vorhanden)
        var groupMap: [String: ContactGroup] = [:]
        for exportGroup in importData.groups {
            let group = ContactGroup(
                name: exportGroup.name,
                icon: exportGroup.icon,
                colorHex: exportGroup.colorHex,
                contactIntervalDays: exportGroup.contactIntervalDays,
                warningThresholdDays: exportGroup.warningThresholdDays,
                priority: exportGroup.priority
            )
            context.insert(group)
            groupMap[exportGroup.name] = group
        }
        
        // Kontakte importieren
        for exportContact in importData.contacts {
            let contact = TrackedContact(
                firstName: exportContact.firstName,
                lastName: exportContact.lastName,
                nickname: exportContact.nickname,
                birthday: exportContact.birthday
            )
            contact.notes = exportContact.notes
            contact.isActive = exportContact.isActive
            
            if let groupName = exportContact.groupName {
                contact.group = groupMap[groupName]
            }
            
            context.insert(contact)
        }
        
        return (contacts: importData.contacts.count, groups: importData.groups.count)
    }
}

/// UTType für den Export
extension UTType {
    static let cmsExport = UTType(exportedAs: "com.cmsfamilyfriends.export", conformingTo: .json)
}
