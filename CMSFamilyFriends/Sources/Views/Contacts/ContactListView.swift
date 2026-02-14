import SwiftUI
import SwiftData

/// Kontaktliste
struct ContactListView: View {
    @Query(sort: \TrackedContact.lastName) private var contacts: [TrackedContact]
    @State private var showingAddContact = false
    @State private var selectedContact: TrackedContact?
    @State private var sortOrder: SortOrder = .name
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case lastContact = "Letzter Kontakt"
        case urgency = "Dringlichkeit"
    }
    
    var sortedContacts: [TrackedContact] {
        switch sortOrder {
        case .name:
            return contacts.sorted { $0.lastName < $1.lastName }
        case .lastContact:
            return contacts.sorted { ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast) }
        case .urgency:
            return contacts.sorted { $0.urgencyLevel > $1.urgencyLevel }
        }
    }
    
    var body: some View {
        VStack {
            // Toolbar
            HStack {
                Picker("Sortierung", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
                
                Spacer()
                
                Button(action: { showingAddContact = true }) {
                    Label("Kontakt hinzufügen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            
            // Kontaktliste
            List(sortedContacts, id: \.id, selection: $selectedContact) { contact in
                ContactRowView(contact: contact)
                    .tag(contact)
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView()
        }
    }
}

/// Einzelne Zeile in der Kontaktliste
struct ContactRowView: View {
    let contact: TrackedContact
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 40, height: 40)
                
                if let imageData = contact.profileImageData,
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .clipShape(Circle())
                        .frame(width: 40, height: 40)
                } else {
                    Text(contact.firstName.prefix(1))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.fullName)
                        .fontWeight(.medium)
                    
                    if contact.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    if let days = contact.daysUntilBirthday, days <= 7 {
                        Text("🎂")
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 16) {
                    if let days = contact.daysSinceLastContact {
                        Label("vor \(days) Tagen", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let group = contact.group {
                        Label(group.name, systemImage: group.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Letzte Kommunikationskanäle
            HStack(spacing: 4) {
                // TODO: Zeige Icons der letzten genutzten Kanäle
            }
        }
        .padding(.vertical, 4)
    }
    
    private var avatarColor: Color {
        let level = contact.urgencyLevel
        switch level {
        case 0..<0.5: return .blue
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .orange
        default: return .red
        }
    }
}

/// View zum Hinzufügen eines neuen Kontakts
struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var nickname = ""
    @State private var notes = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Neuen Kontakt hinzufügen")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                TextField("Vorname", text: $firstName)
                TextField("Nachname", text: $lastName)
                TextField("Spitzname (optional)", text: $nickname)
                TextField("Notizen (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Speichern") {
                    let contact = TrackedContact(
                        firstName: firstName,
                        lastName: lastName,
                        nickname: nickname.isEmpty ? nil : nickname
                    )
                    contact.notes = notes.isEmpty ? nil : notes
                    modelContext.insert(contact)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(firstName.isEmpty && lastName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}
