import Foundation
import Contacts

/// Service für Apple Kontakte Integration
actor ContactsService {
    private let store = CNContactStore()
    
    struct ContactInfo {
        let identifier: String
        let firstName: String
        let lastName: String
        let nickname: String?
        let birthday: Date?
        let phoneNumbers: [String]
        let emailAddresses: [String]
        let imageData: Data?
    }
    
    /// Berechtigung für Kontakte-Zugriff anfordern
    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }
    
    /// Alle Kontakte abrufen
    func fetchAllContacts() async throws -> [ContactInfo] {
        let granted = try await requestAccess()
        guard granted else {
            throw ServiceError.notAuthorized("Kontakte-Zugriff nicht gewährt")
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [ContactInfo] = []
        
        try store.enumerateContacts(with: request) { contact, _ in
            let birthday = contact.birthday?.date
            
            let info = ContactInfo(
                identifier: contact.identifier,
                firstName: contact.givenName,
                lastName: contact.familyName,
                nickname: contact.nickname.isEmpty ? nil : contact.nickname,
                birthday: birthday,
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                emailAddresses: contact.emailAddresses.map { $0.value as String },
                imageData: contact.thumbnailImageData
            )
            contacts.append(info)
        }
        
        return contacts
    }
    
    /// Kontakt nach Telefonnummer suchen
    func findContact(byPhoneNumber phone: String) async throws -> ContactInfo? {
        let contacts = try await fetchAllContacts()
        let normalizedPhone = normalizePhoneNumber(phone)
        
        return contacts.first { contact in
            contact.phoneNumbers.contains { normalizePhoneNumber($0) == normalizedPhone }
        }
    }
    
    /// Kontakt nach E-Mail suchen
    func findContact(byEmail email: String) async throws -> ContactInfo? {
        let contacts = try await fetchAllContacts()
        let loweredEmail = email.lowercased()
        
        return contacts.first { contact in
            contact.emailAddresses.contains { $0.lowercased() == loweredEmail }
        }
    }
    
    /// Telefonnummer normalisieren (nur Ziffern + ggf. +)
    private func normalizePhoneNumber(_ number: String) -> String {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        return number.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
    }
}
