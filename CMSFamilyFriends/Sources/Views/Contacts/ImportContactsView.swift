import SwiftUI
import SwiftData
import Contacts

/// Kontakte aus der macOS Kontakte-App importieren
struct ImportContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    @Query private var existingContacts: [TrackedContact]
    
    @State private var appleContacts: [ImportableContact] = []
    @State private var selectedContacts: Set<String> = []  // Apple Contact IDs
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var step: ImportStep = .selectContacts
    @State private var selectedGroup: ContactGroup?
    @State private var showNewGroupForm = false
    @State private var newGroupName = ""
    @State private var newGroupInterval = 30
    @State private var newGroupIcon = "person.2.fill"
    @State private var newGroupColor = "#007AFF"
    @State private var importedCount = 0
    @State private var skippedCount = 0
    
    enum ImportStep {
        case selectContacts
        case chooseGroup
        case done
    }
    
    /// Darstellung eines Apple-Kontakts zum Import
    struct ImportableContact: Identifiable {
        let id: String  // Apple Contact Identifier
        let firstName: String
        let lastName: String
        let nickname: String?
        let birthday: Date?
        let imageData: Data?
        let phoneNumbers: [String]
        let emailAddresses: [String]
        let isAlreadyImported: Bool
        
        var fullName: String {
            [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
    
    var filteredContacts: [ImportableContact] {
        guard !searchText.isEmpty else { return appleContacts }
        let query = searchText.lowercased()
        return appleContacts.filter {
            $0.firstName.lowercased().contains(query) ||
            $0.lastName.lowercased().contains(query) ||
            ($0.nickname?.lowercased().contains(query) ?? false)
        }
    }
    
    var selectableContacts: [ImportableContact] {
        filteredContacts.filter { !$0.isAlreadyImported }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content je nach Step
            switch step {
            case .selectContacts:
                contactSelectionView
            case .chooseGroup:
                groupSelectionView
            case .done:
                importDoneView
            }
        }
        .frame(width: 600, height: 650)
        .task {
            await loadAppleContacts()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            switch step {
            case .selectContacts:
                Text("Kontakte importieren")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                if !selectedContacts.isEmpty {
                    Text("\(selectedContacts.count) ausgewählt")
                        .foregroundStyle(.secondary)
                }
            case .chooseGroup:
                Button(action: { step = .selectContacts }) {
                    Label("Zurück", systemImage: "chevron.left")
                }
                Spacer()
                Text("Gruppe wählen")
                    .font(.title2).fontWeight(.bold)
                Spacer()
            case .done:
                Spacer()
                Text("Import abgeschlossen")
                    .font(.title2).fontWeight(.bold)
                Spacer()
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Step 1: Kontakte auswählen
    
    private var contactSelectionView: some View {
        VStack(spacing: 0) {
            // Suchfeld + Alle-Auswählen
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Kontakte durchsuchen...", text: $searchText)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                if !selectableContacts.isEmpty {
                    Button(allSelectableSelected ? "Keine auswählen" : "Alle auswählen") {
                        if allSelectableSelected {
                            selectedContacts.removeAll()
                        } else {
                            selectedContacts = Set(selectableContacts.map(\.id))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if isLoading {
                Spacer()
                ProgressView("Kontakte werden geladen...")
                Spacer()
            } else if let error = loadError {
                Spacer()
                ContentUnavailableView {
                    Label("Fehler", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
                Spacer()
            } else if filteredContacts.isEmpty {
                Spacer()
                ContentUnavailableView(
                    searchText.isEmpty ? "Keine Kontakte gefunden" : "Keine Treffer",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(searchText.isEmpty
                        ? "Die macOS Kontakte-App enthält keine Kontakte."
                        : "Kein Kontakt passt zu \"\(searchText)\".")
                )
                Spacer()
            } else {
                List {
                    // Bereits importierte (ausgegraut)
                    let alreadyImported = filteredContacts.filter(\.isAlreadyImported)
                    let notImported = filteredContacts.filter { !$0.isAlreadyImported }
                    
                    if !notImported.isEmpty {
                        Section("Verfügbar (\(notImported.count))") {
                            ForEach(notImported) { contact in
                                contactRow(contact, selectable: true)
                            }
                        }
                    }
                    
                    if !alreadyImported.isEmpty {
                        Section("Bereits importiert (\(alreadyImported.count))") {
                            ForEach(alreadyImported) { contact in
                                contactRow(contact, selectable: false)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            
            Divider()
            
            // Footer mit Weiter-Button
            HStack {
                Text("\(appleContacts.count) Kontakte in der Kontakte-App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Weiter →") {
                    step = .chooseGroup
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedContacts.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private var allSelectableSelected: Bool {
        !selectableContacts.isEmpty && selectableContacts.allSatisfy { selectedContacts.contains($0.id) }
    }
    
    private func contactRow(_ contact: ImportableContact, selectable: Bool) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            if selectable {
                Image(systemName: selectedContacts.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedContacts.contains(contact.id) ? .blue : .secondary)
                    .font(.title3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.5))
                    .font(.title3)
            }
            
            // Avatar
            if let imageData = contact.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(contact.firstName.prefix(1) + contact.lastName.prefix(1))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
            }
            
            // Name
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.fullName)
                    .fontWeight(.medium)
                    .foregroundStyle(selectable ? .primary : .secondary)
                
                if let nickname = contact.nickname {
                    Text("\"\(nickname)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Info
            if !contact.phoneNumbers.isEmpty {
                Image(systemName: "phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !contact.emailAddresses.isEmpty {
                Image(systemName: "envelope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectable else { return }
            if selectedContacts.contains(contact.id) {
                selectedContacts.remove(contact.id)
            } else {
                selectedContacts.insert(contact.id)
            }
        }
        .opacity(selectable ? 1.0 : 0.6)
    }
    
    // MARK: - Step 2: Gruppe wählen
    
    private var groupSelectionView: some View {
        VStack(spacing: 16) {
            Text("\(selectedContacts.count) Kontakt(e) ausgewählt – in welche Gruppe?")
                .font(.headline)
                .padding(.top)
            
            List {
                // Bestehende Gruppen
                Section("Bestehende Gruppen") {
                    ForEach(groups, id: \.id) { group in
                        groupRow(group)
                    }
                    
                    if groups.isEmpty {
                        Text("Noch keine Gruppen vorhanden")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                
                // Keine Gruppe
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.title2)
                            .foregroundStyle(.gray)
                            .frame(width: 36)
                        
                        VStack(alignment: .leading) {
                            Text("Ohne Gruppe importieren")
                                .fontWeight(.medium)
                            Text("Gruppe kann später zugewiesen werden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedGroup == nil && !showNewGroupForm {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedGroup = nil
                        showNewGroupForm = false
                    }
                }
                
                // Neue Gruppe erstellen
                Section("Neue Gruppe erstellen") {
                    VStack(alignment: .leading, spacing: 12) {
                        if showNewGroupForm {
                            newGroupFormContent
                        } else {
                            Button(action: { showNewGroupForm = true }) {
                                Label("Neue Gruppe anlegen", systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Zurück") {
                    step = .selectContacts
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Importieren") {
                    performImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(showNewGroupForm && newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }
    
    private func groupRow(_ group: ContactGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.icon)
                .font(.title2)
                .foregroundStyle(Color(hex: group.colorHex) ?? .blue)
                .frame(width: 36)
            
            VStack(alignment: .leading) {
                Text(group.name)
                    .fontWeight(.medium)
                Text("Intervall: alle \(group.contactIntervalDays) Tage · \(group.contacts.count) Kontakte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if selectedGroup?.id == group.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedGroup = group
            showNewGroupForm = false
        }
    }
    
    private var newGroupFormContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Gruppenname", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Kontakt-Intervall:")
                    .font(.caption)
                Stepper("\(newGroupInterval) Tage", value: $newGroupInterval, in: 1...365)
                    .font(.caption)
            }
            
            Picker("Symbol", selection: $newGroupIcon) {
                Label("Personen", systemImage: "person.2.fill").tag("person.2.fill")
                Label("Herz", systemImage: "heart.fill").tag("heart.fill")
                Label("Haus", systemImage: "house.fill").tag("house.fill")
                Label("Stern", systemImage: "star.fill").tag("star.fill")
                Label("Koffer", systemImage: "briefcase.fill").tag("briefcase.fill")
                Label("Sportler", systemImage: "figure.run").tag("figure.run")
            }
            .pickerStyle(.menu)
            .font(.caption)
            
            Button("Abbrechen") {
                showNewGroupForm = false
                newGroupName = ""
            }
            .font(.caption)
        }
    }
    
    // MARK: - Step 3: Fertig
    
    private var importDoneView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("\(importedCount) Kontakt(e) importiert")
                .font(.title2)
                .fontWeight(.bold)
            
            if skippedCount > 0 {
                Text("\(skippedCount) bereits vorhanden – übersprungen")
                    .foregroundStyle(.secondary)
            }
            
            if let group = selectedGroup {
                Text("Zugewiesen an: \(group.name)")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
        }
    }
    
    // MARK: - Daten laden
    
    private func loadAppleContacts() async {
        isLoading = true
        loadError = nil
        
        let store = CNContactStore()
        
        // Status prüfen
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .denied, .restricted:
            loadError = "Kontakte-Zugriff nicht erlaubt. Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Kontakte aktivieren."
            isLoading = false
            return
        case .notDetermined:
            do {
                let granted = try await store.requestAccess(for: .contacts)
                if !granted {
                    loadError = "Kontakte-Zugriff wurde nicht gewährt."
                    isLoading = false
                    return
                }
            } catch {
                loadError = "Fehler beim Anfordern der Berechtigung: \(error.localizedDescription)"
                isLoading = false
                return
            }
        case .authorized:
            break
        @unknown default:
            break
        }
        
        // Kontakte laden
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .familyName
        
        let importedIdentifiers = Set(existingContacts.compactMap(\.appleContactIdentifier))
        
        var loaded: [ImportableContact] = []
        
        do {
            try store.enumerateContacts(with: request) { cnContact, _ in
                // Leere Kontakte überspringen
                guard !cnContact.givenName.isEmpty || !cnContact.familyName.isEmpty else { return }
                
                let contact = ImportableContact(
                    id: cnContact.identifier,
                    firstName: cnContact.givenName,
                    lastName: cnContact.familyName,
                    nickname: cnContact.nickname.isEmpty ? nil : cnContact.nickname,
                    birthday: cnContact.birthday?.date,
                    imageData: cnContact.thumbnailImageData,
                    phoneNumbers: cnContact.phoneNumbers.map { $0.value.stringValue },
                    emailAddresses: cnContact.emailAddresses.map { $0.value as String },
                    isAlreadyImported: importedIdentifiers.contains(cnContact.identifier)
                )
                loaded.append(contact)
            }
        } catch {
            loadError = "Fehler beim Laden der Kontakte: \(error.localizedDescription)"
        }
        
        appleContacts = loaded
        isLoading = false
    }
    
    // MARK: - Import durchführen
    
    private func performImport() {
        // Ggf. neue Gruppe erstellen
        var targetGroup = selectedGroup
        
        if showNewGroupForm {
            let trimmedName = newGroupName.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { return }
            
            let newGroup = ContactGroup(
                name: trimmedName,
                icon: newGroupIcon,
                colorHex: newGroupColor,
                contactIntervalDays: newGroupInterval
            )
            modelContext.insert(newGroup)
            targetGroup = newGroup
        }
        
        // Kontakte importieren
        importedCount = 0
        skippedCount = 0
        
        let importedIdentifiers = Set(existingContacts.compactMap(\.appleContactIdentifier))
        
        for appleContact in appleContacts where selectedContacts.contains(appleContact.id) {
            // Duplikat-Check
            if importedIdentifiers.contains(appleContact.id) {
                skippedCount += 1
                continue
            }
            
            let tracked = TrackedContact(
                firstName: appleContact.firstName,
                lastName: appleContact.lastName,
                nickname: appleContact.nickname,
                appleContactIdentifier: appleContact.id,
                birthday: appleContact.birthday
            )
            tracked.profileImageData = appleContact.imageData
            tracked.group = targetGroup
            modelContext.insert(tracked)
            importedCount += 1
        }
        
        step = .done
    }
}

#Preview {
    ImportContactsView()
        .modelContainer(for: [TrackedContact.self, ContactGroup.self])
}
