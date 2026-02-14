import SwiftUI
import SwiftData

/// Kontaktliste mit Suche, Gruppenfilter, Sortierung
struct ContactListView: View {
    @Query(sort: \TrackedContact.lastName) private var contacts: [TrackedContact]
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    @Binding var searchText: String
    @State private var showingAddContact = false
    @State private var showingImportContacts = false
    @State private var selectedContact: TrackedContact?
    @State private var sortOrder: SortOrder = .name
    @State private var selectedGroupFilter: ContactGroup?
    @State private var contactToDelete: TrackedContact?
    @State private var showDeleteConfirmation = false
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case lastContact = "Letzter Kontakt"
        case urgency = "Dringlichkeit"
    }
    
    var filteredAndSortedContacts: [TrackedContact] {
        var result = contacts
        
        // Gruppenfilter
        if let group = selectedGroupFilter {
            result = result.filter { $0.group?.id == group.id }
        }
        
        // Suchfilter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query) ||
                ($0.nickname?.lowercased().contains(query) ?? false)
            }
        }
        
        // Sortierung
        switch sortOrder {
        case .name:
            result.sort { $0.lastName < $1.lastName }
        case .lastContact:
            result.sort { ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast) }
        case .urgency:
            result.sort { $0.urgencyLevel > $1.urgencyLevel }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Sortierung", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
                
                // Gruppenfilter
                Picker("Gruppe", selection: $selectedGroupFilter) {
                    Text("Alle Gruppen").tag(nil as ContactGroup?)
                    ForEach(groups, id: \.id) { group in
                        Label(group.name, systemImage: group.icon).tag(group as ContactGroup?)
                    }
                }
                .frame(width: 180)
                
                Spacer()
                
                Text("\(filteredAndSortedContacts.count) Kontakte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(action: { showingImportContacts = true }) {
                    Label("Aus Kontakte importieren", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                
                Button(action: { showingAddContact = true }) {
                    Label("Manuell hinzufügen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Kontaktliste
            if filteredAndSortedContacts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Noch keine Kontakte" : "Keine Treffer",
                    systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Füge deinen ersten Kontakt hinzu."
                        : "Kein Kontakt passt zu \"\(searchText)\".")
                )
            } else {
                List(filteredAndSortedContacts, id: \.id, selection: $selectedContact) { contact in
                    ContactRowView(contact: contact)
                        .tag(contact)
                        .contextMenu {
                            Button("Löschen", role: .destructive) {
                                contactToDelete = contact
                                showDeleteConfirmation = true
                            }
                        }
                        .accessibilityLabel("\(contact.fullName), \(contact.isOverdue ? "überfällig" : "aktuell")")
                }
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView()
        }
        .sheet(isPresented: $showingImportContacts) {
            ImportContactsView()
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact)
        }
        .confirmationDialog(
            "Kontakt löschen?",
            isPresented: $showDeleteConfirmation,
            presenting: contactToDelete
        ) { contact in
            Button("Löschen", role: .destructive) {
                deleteContact(contact)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { contact in
            Text("\"\(contact.fullName)\" wirklich löschen? Alle Kommunikationsdaten dieses Kontakts gehen verloren.")
        }
    }
    
    @Environment(\.modelContext) private var modelContext
    
    private func deleteContact(_ contact: TrackedContact) {
        modelContext.delete(contact)
    }
}

/// Einzelne Zeile in der Kontaktliste
struct ContactRowView: View {
    let contact: TrackedContact
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar (nutzt wiederverwendbare Komponente)
            ContactAvatarView(contact: contact, size: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.fullName)
                        .fontWeight(.medium)
                    
                    if contact.isOverdue {
                        UrgencyBadge(level: contact.urgencyLevel)
                    }
                    
                    if let days = contact.daysUntilBirthday, days <= 7 {
                        Text("🎂")
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 16) {
                    if let date = contact.lastContactDate {
                        Label(date.relativeString, systemImage: "clock")
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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contact Detail View
struct ContactDetailView: View {
    let contact: TrackedContact
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            ContactAvatarView(contact: contact, size: 80)
            
            Text(contact.fullName)
                .font(.title)
                .fontWeight(.bold)
            
            if let nickname = contact.nickname {
                Text("\"\(nickname)\"")
                    .foregroundStyle(.secondary)
            }
            
            // Stats
            HStack(spacing: 32) {
                statItem("Letzter Kontakt",
                         value: contact.lastContactDate?.relativeString ?? "Nie")
                statItem("Kommunikationen",
                         value: "\(contact.communicationEvents.count)")
                statItem("Gruppe",
                         value: contact.group?.name ?? "Keine")
            }
            
            Divider()
            
            // Kommunikationshistorie
            if contact.communicationEvents.isEmpty {
                Text("Noch keine Kommunikation erfasst")
                    .foregroundStyle(.secondary)
            } else {
                List(contact.communicationEvents.sorted { $0.date > $1.date }.prefix(20), id: \.id) { event in
                    HStack {
                        Text(event.date.relativeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(event.channel.rawValue)
                            .font(.caption)
                        Spacer()
                        Text(event.direction == .incoming ? "↙" : "↗")
                    }
                }
            }
            
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func statItem(_ label: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// View zum Hinzufügen eines neuen Kontakts
struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var nickname = ""
    @State private var notes = ""
    @State private var selectedGroup: ContactGroup?
    
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
                
                Picker("Gruppe", selection: $selectedGroup) {
                    Text("Keine Gruppe").tag(nil as ContactGroup?)
                    ForEach(groups, id: \.id) { group in
                        Label(group.name, systemImage: group.icon).tag(group as ContactGroup?)
                    }
                }
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
                    contact.group = selectedGroup
                    modelContext.insert(contact)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(firstName.isEmpty && lastName.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 420)
    }
}
