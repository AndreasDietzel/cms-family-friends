import SwiftUI
import SwiftData

/// Kontaktliste mit Suche, Gruppenfilter, Sortierung
struct ContactListView: View {
    @Query(sort: \TrackedContact.lastName) private var contacts: [TrackedContact]
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    @State private var searchText = ""
    @State private var showingAddContact = false
    @State private var showingImportContacts = false
    @State private var selectedContact: TrackedContact?
    @State private var sortOrder: SortOrder = .name
    @State private var selectedGroupFilter: ContactGroup?
    @State private var contactToDelete: TrackedContact?
    @State private var showDeleteConfirmation = false
    @State private var showMeetingDatePicker = false
    @State private var meetingContact: TrackedContact?
    @State private var meetingDate = Date()
    
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
            // Suchleiste
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Kontakte durchsuchen...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)
            
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
                            Button(action: {
                                meetingContact = contact
                                meetingDate = Date()
                                showMeetingDatePicker = true
                            }) {
                                Label("Treffen dokumentieren", systemImage: "person.2.circle.fill")
                            }
                            Divider()
                            Button("Löschen", role: .destructive) {
                                contactToDelete = contact
                                showDeleteConfirmation = true
                            }
                        }
                        .accessibilityLabel("\(contact.fullName), \(contact.isOverdue ? "überfällig" : "aktuell")")
                }
            }
        }
        .sheet(isPresented: $showMeetingDatePicker) {
            if let contact = meetingContact {
                MeetingDatePickerView(contact: contact, initialDate: meetingDate) { date in
                    recordMeeting(for: contact, on: date)
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
    
    /// Real-Life Treffen per Rechtsklick-Kontextmenü dokumentieren
    private func recordMeeting(for contact: TrackedContact, on date: Date = Date()) {
        let event = CommunicationEvent(
            channel: .reallife,
            direction: .mutual,
            date: date,
            summary: "Persönliches Treffen",
            isAutoDetected: false
        )
        event.contact = contact
        modelContext.insert(event)
        if date <= Date() {
            // Nur vergangene/heutige Treffen als letzten Kontakt setzen
            if contact.lastContactDate == nil || date > (contact.lastContactDate ?? .distantPast) {
                contact.lastContactDate = date
            }
        }
    }
}

/// DatePicker-Sheet für Treffen dokumentieren
struct MeetingDatePickerView: View {
    let contact: TrackedContact
    @State var selectedDate: Date
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    
    init(contact: TrackedContact, initialDate: Date = Date(), onConfirm: @escaping (Date) -> Void) {
        self.contact = contact
        self._selectedDate = State(initialValue: initialDate)
        self.onConfirm = onConfirm
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Treffen mit \(contact.fullName)")
                .font(.headline)
            
            DatePicker(
                "Datum & Uhrzeit",
                selection: $selectedDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .frame(maxWidth: 320)
            
            if selectedDate > Date() {
                Label("Geplantes Treffen (Zukunft)", systemImage: "calendar.badge.clock")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            
            HStack {
                Button("Abbrechen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Jetzt (heute)") {
                    selectedDate = Date()
                }
                .buttonStyle(.bordered)
                
                Button("Speichern") {
                    onConfirm(selectedDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
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
    @Bindable var contact: TrackedContact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    
    @State private var isEditing = false
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var editNickname = ""
    @State private var editNotes = ""
    @State private var editGroup: ContactGroup?
    @State private var useCustomInterval = false
    @State private var editCustomInterval = 14
    @State private var showMeetingConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showMeetingDatePicker = false
    @State private var meetingDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                ContactAvatarView(contact: contact, size: 80)
                
                if isEditing {
                    editingHeader
                } else {
                    displayHeader
                }
                
                // Quick-Action: Real-Life Treffen
                if !isEditing {
                    Button(action: { showMeetingDatePicker = true }) {
                        Label("Treffen dokumentieren", systemImage: "person.2.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .help("Persönliches Treffen dokumentieren – Datum wählbar")
                    .sheet(isPresented: $showMeetingDatePicker) {
                        MeetingDatePickerView(contact: contact, initialDate: meetingDate) { date in
                            recordRealLifeMeeting(on: date)
                        }
                    }
                }
                
                if showMeetingConfirmation {
                    Label("Treffen dokumentiert ✓", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Divider()
                
                // Gruppe & Zyklus
                groupAndCycleSection
                
                Divider()
                
                // Kommunikationshistorie
                communicationSection
                
                // Buttons
                HStack(spacing: 12) {
                    if isEditing {
                        Button("Abbrechen") {
                            isEditing = false
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Button("Speichern") {
                            saveChanges()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Bearbeiten") {
                            startEditing()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Löschen", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        
                        Button("Schließen") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding()
        }
        .frame(width: 520, height: 700)
        .confirmationDialog(
            "Kontakt löschen?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Löschen", role: .destructive) {
                modelContext.delete(contact)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\"\(contact.fullName)\" und alle zugehörigen Kommunikationsdaten wirklich löschen?")
        }
    }
    
    // MARK: - Display Header
    
    private var displayHeader: some View {
        VStack(spacing: 4) {
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
            }
        }
    }
    
    // MARK: - Editing Header
    
    private var editingHeader: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Vorname", text: $editFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Nachname", text: $editLastName)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Spitzname (optional)", text: $editNickname)
                .textFieldStyle(.roundedBorder)
            TextField("Notizen", text: $editNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .frame(maxWidth: 400)
    }
    
    // MARK: - Gruppe & Zyklus
    
    private var groupAndCycleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gruppe & Kontaktzyklus")
                .font(.headline)
            
            if isEditing {
                // Gruppen-Auswahl
                Picker("Gruppe", selection: $editGroup) {
                    Text("Keine Gruppe").tag(nil as ContactGroup?)
                    ForEach(groups, id: \.id) { group in
                        Label("\(group.name) (alle \(group.contactIntervalDays) Tage)",
                              systemImage: group.icon)
                            .tag(group as ContactGroup?)
                    }
                }
                .pickerStyle(.menu)
                
                Divider()
                
                // Individueller Zyklus
                Toggle("Eigenen Kontaktzyklus verwenden", isOn: $useCustomInterval)
                
                if useCustomInterval {
                    HStack {
                        Text("Alle")
                        TextField("", value: $editCustomInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("Tage kontaktieren")
                    }
                    .font(.callout)
                    
                    if let groupInterval = editGroup?.contactIntervalDays {
                        Text("Überschreibt den Gruppen-Zyklus von \(groupInterval) Tagen")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                // Anzeige
                HStack {
                    Image(systemName: contact.group?.icon ?? "person.fill.questionmark")
                        .foregroundStyle(Color(hex: contact.group?.colorHex ?? "#999") ?? .gray)
                    Text(contact.group?.name ?? "Keine Gruppe")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let interval = contact.effectiveIntervalDays {
                        Text("alle \(interval) Tage")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if contact.customContactIntervalDays != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.clock")
                            .font(.caption)
                        Text("Eigener Zyklus: \(contact.customContactIntervalDays!) Tage")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        if let groupInterval = contact.group?.contactIntervalDays {
                            Text("(Gruppe: \(groupInterval) Tage)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if let notes = contact.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Kommunikation
    
    private var communicationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kommunikationshistorie")
                .font(.headline)
            
            if contact.communicationEvents.isEmpty {
                Text("Noch keine Kommunikation erfasst")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(contact.communicationEvents.sorted { $0.date > $1.date }.prefix(15), id: \.id) { event in
                    HStack {
                        Text(event.date.relativeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Label(event.channel.displayName, systemImage: event.channel.icon)
                            .font(.caption)
                        Spacer()
                        Text(event.direction == .incoming ? "↙" : "↗")
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func startEditing() {
        editFirstName = contact.firstName
        editLastName = contact.lastName
        editNickname = contact.nickname ?? ""
        editNotes = contact.notes ?? ""
        editGroup = contact.group
        useCustomInterval = contact.customContactIntervalDays != nil
        editCustomInterval = contact.customContactIntervalDays ?? contact.group?.contactIntervalDays ?? 14
        isEditing = true
    }
    
    private func saveChanges() {
        contact.firstName = editFirstName
        contact.lastName = editLastName
        contact.nickname = editNickname.isEmpty ? nil : editNickname
        contact.notes = editNotes.isEmpty ? nil : editNotes
        contact.group = editGroup
        contact.customContactIntervalDays = useCustomInterval ? max(1, editCustomInterval) : nil
        isEditing = false
    }
    
    /// Real-Life Treffen mit Datumswahl dokumentieren
    private func recordRealLifeMeeting(on date: Date = Date()) {
        let event = CommunicationEvent(
            channel: .reallife,
            direction: .mutual,
            date: date,
            summary: "Persönliches Treffen",
            isAutoDetected: false
        )
        event.contact = contact
        modelContext.insert(event)
        if date <= Date() {
            if contact.lastContactDate == nil || date > (contact.lastContactDate ?? .distantPast) {
                contact.lastContactDate = date
            }
        }
        
        withAnimation {
            showMeetingConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showMeetingConfirmation = false
            }
        }
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
