import SwiftUI
import SwiftData

/// Gruppenliste und -verwaltung
struct GroupListView: View {
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    @Query(filter: #Predicate<TrackedContact> { $0.group == nil }) private var unassignedContacts: [TrackedContact]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGroup = false
    @State private var groupToDelete: ContactGroup?
    @State private var showDeleteConfirmation = false
    @State private var showBatchAssign = false
    @State private var batchTargetGroup: ContactGroup?
    
    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Gruppen", systemImage: "person.3")
                    } description: {
                        Text("Erstelle deine erste Gruppe oder nutze die Standard-Gruppen.")
                    } actions: {
                        Button("Standard-Gruppen erstellen") {
                            createDefaultGroups()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    // Nicht zugeordnete Kontakte
                    if !unassignedContacts.isEmpty {
                        Section {
                            HStack {
                                Image(systemName: "person.fill.questionmark")
                                    .foregroundStyle(.orange)
                                Text("\(unassignedContacts.count) Kontakt(e) ohne Gruppe")
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Zuordnen…") {
                                    showBatchAssign = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    // Gruppen
                    Section {
                        ForEach(groups, id: \.id) { group in
                            GroupDetailRow(group: group)
                                .contextMenu {
                                    Button("Löschen", role: .destructive) {
                                        groupToDelete = group
                                        showDeleteConfirmation = true
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Kontaktgruppen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddGroup = true }) {
                        Label("Gruppe hinzufügen", systemImage: "plus")
                    }
                }
                
                if groups.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Button("Standard-Gruppen erstellen") {
                            createDefaultGroups()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            AddGroupView()
        }
        .sheet(isPresented: $showBatchAssign) {
            BatchAssignView(contacts: unassignedContacts, groups: groups)
        }
        .confirmationDialog(
            "Gruppe löschen?",
            isPresented: $showDeleteConfirmation,
            presenting: groupToDelete
        ) { group in
            Button("Löschen", role: .destructive) {
                modelContext.delete(group)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { group in
            Text("Gruppe \"\(group.name)\" mit \(group.contacts.count) Kontakt(en) wirklich löschen?")
        }
    }
    
    private func createDefaultGroups() {
        for defaults in ContactGroup.defaultGroups {
            let group = ContactGroup(
                name: defaults.name,
                icon: defaults.icon,
                colorHex: defaults.color,
                contactIntervalDays: defaults.interval,
                priority: defaults.priority
            )
            modelContext.insert(group)
        }
    }
}

struct GroupDetailRow: View {
    @Bindable var group: ContactGroup
    @State private var showEditSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: group.icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: group.colorHex) ?? .blue)
                
                VStack(alignment: .leading) {
                    Text(group.name)
                        .font(.headline)
                    Text("Kontakt alle \(group.contactIntervalDays) Tage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(group.contacts.count) Kontakte")
                        .font(.subheadline)
                    
                    if group.overdueCount > 0 {
                        Text("\(group.overdueCount) überfällig")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.red)
                            .clipShape(Capsule())
                    }
                }
                
                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Gruppe bearbeiten")
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEditSheet) {
            EditGroupView(group: group)
        }
    }
}

// MARK: - Gruppe bearbeiten
struct EditGroupView: View {
    @Bindable var group: ContactGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var interval = 14
    @State private var warningDays = 3
    @State private var icon = "person.2"
    @State private var priority = 50
    @State private var showDeleteGroupConfirmation = false
    
    let availableIcons = [
        "house.fill", "heart.fill", "person.2.fill",
        "person.fill", "briefcase.fill", "star.fill",
        "figure.walk", "sportscourt.fill", "music.note"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Gruppe bearbeiten")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                TextField("Gruppenname", text: $name)
                
                Section("Kontaktzyklus") {
                    Stepper("Intervall: \(interval) Tage", value: $interval, in: 1...365)
                    Text("Kontakte in dieser Gruppe sollten alle \(interval) Tage kontaktiert werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Stepper("Warnung: \(warningDays) Tage vorher", value: $warningDays, in: 1...interval)
                }
                
                Section("Darstellung") {
                    Stepper("Priorität: \(priority)", value: $priority, in: 0...100)
                    
                    Picker("Symbol", selection: $icon) {
                        ForEach(availableIcons, id: \.self) { iconName in
                            Label(iconName, systemImage: iconName).tag(iconName)
                        }
                    }
                }
                
                Section("Kontakte (\(group.contacts.count))") {
                    if group.contacts.isEmpty {
                        Text("Keine Kontakte in dieser Gruppe")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(group.contacts.sorted { $0.lastName < $1.lastName }, id: \.id) { contact in
                            HStack {
                                Text(contact.fullName)
                                Spacer()
                                if let custom = contact.customContactIntervalDays {
                                    Text("eigener Zyklus: \(custom)d")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                if contact.isOverdue {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                }
                                Button(action: {
                                    contact.group = nil
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Aus Gruppe entfernen")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Gruppe löschen", role: .destructive) {
                    showDeleteGroupConfirmation = true
                }
                .foregroundStyle(.red)
                
                Spacer()
                
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Speichern") {
                    group.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    group.contactIntervalDays = max(1, interval)
                    group.warningThresholdDays = max(1, warningDays)
                    group.icon = icon
                    group.priority = priority
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 550)
        .confirmationDialog(
            "Gruppe löschen?",
            isPresented: $showDeleteGroupConfirmation
        ) {
            Button("Löschen", role: .destructive) {
                for contact in group.contacts {
                    contact.group = nil
                }
                modelContext.delete(group)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gruppe \"\(group.name)\" löschen? Die \(group.contacts.count) Kontakte bleiben erhalten, verlieren aber ihre Gruppenzuordnung.")
        }
        .onAppear {
            name = group.name
            interval = group.contactIntervalDays
            warningDays = group.warningThresholdDays
            icon = group.icon
            priority = group.priority
        }
    }
}

struct AddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var interval = 14
    @State private var icon = "person.2"
    @State private var colorHex = "#007AFF"
    @State private var priority = 50
    @State private var validationError: String?
    @FocusState private var nameFieldFocused: Bool
    
    let availableIcons = [
        "house.fill", "heart.fill", "person.2.fill",
        "person.fill", "briefcase.fill", "star.fill",
        "figure.walk", "sportscourt.fill", "music.note"
    ]
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && interval >= 1
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Neue Gruppe erstellen")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gruppenname")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("z.B. Familie, Sportverein...", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Stepper("Kontakt-Intervall: \(interval) Tage", value: $interval, in: 1...365)
                    Text("Wie oft sollten Kontakte in dieser Gruppe kontaktiert werden?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Stepper("Priorität: \(priority)", value: $priority, in: 0...100)
                
                Picker("Symbol", selection: $icon) {
                    ForEach(availableIcons, id: \.self) { iconName in
                        Label(iconName, systemImage: iconName).tag(iconName)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding()
            
            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Erstellen") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        validationError = "Name darf nicht leer sein"
                        return
                    }
                    guard interval >= 1 else {
                        validationError = "Intervall muss mindestens 1 Tag sein"
                        return
                    }
                    let group = ContactGroup(
                        name: trimmed,
                        icon: icon,
                        colorHex: colorHex,
                        contactIntervalDays: interval,
                        priority: priority
                    )
                    modelContext.insert(group)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
        .onAppear {
            // Focus auf Namensfeld setzen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFieldFocused = true
            }
        }
    }
}

// MARK: - Batch-Zuweisung nicht zugeordneter Kontakte
struct BatchAssignView: View {
    let contacts: [TrackedContact]
    let groups: [ContactGroup]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedContacts: Set<UUID> = []
    @State private var targetGroup: ContactGroup?
    @State private var assignedCount = 0
    @State private var isDone = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Kontakte zuordnen")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                if !selectedContacts.isEmpty {
                    Text("\(selectedContacts.count) ausgewählt")
                        .foregroundStyle(.secondary)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if isDone {
                // Ergebnis
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("\(assignedCount) Kontakt(e) zugeordnet")
                        .font(.title3).fontWeight(.bold)
                    if let group = targetGroup {
                        Text("Gruppe: \(group.name)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Schließen") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom)
                }
            } else {
                // Kontaktliste mit Checkboxen
                HStack {
                    Button(allSelected ? "Keine auswählen" : "Alle auswählen") {
                        if allSelected {
                            selectedContacts.removeAll()
                        } else {
                            selectedContacts = Set(contacts.map(\.id))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                
                List(contacts.sorted { $0.lastName < $1.lastName }, id: \.id) { contact in
                    HStack(spacing: 12) {
                        Image(systemName: selectedContacts.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedContacts.contains(contact.id) ? .blue : .secondary)
                            .font(.title3)
                        
                        Text(contact.fullName)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        if let days = contact.daysSinceLastContact {
                            Text("vor \(days)d")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedContacts.contains(contact.id) {
                            selectedContacts.remove(contact.id)
                        } else {
                            selectedContacts.insert(contact.id)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                
                Divider()
                
                // Gruppen-Auswahl + Zuordnen
                HStack(spacing: 12) {
                    Text("Zuordnen an:")
                        .font(.callout)
                    
                    Picker("Gruppe", selection: $targetGroup) {
                        Text("Gruppe wählen…").tag(nil as ContactGroup?)
                        ForEach(groups, id: \.id) { group in
                            Label("\(group.name) (\(group.contactIntervalDays)d)", systemImage: group.icon)
                                .tag(group as ContactGroup?)
                        }
                    }
                    .frame(width: 220)
                    
                    Spacer()
                    
                    Button("Zuordnen") {
                        performAssign()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedContacts.isEmpty || targetGroup == nil)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 500)
    }
    
    private var allSelected: Bool {
        !contacts.isEmpty && contacts.allSatisfy { selectedContacts.contains($0.id) }
    }
    
    private func performAssign() {
        guard let group = targetGroup else { return }
        assignedCount = 0
        for contact in contacts where selectedContacts.contains(contact.id) {
            contact.group = group
            assignedCount += 1
        }
        isDone = true
    }
}
