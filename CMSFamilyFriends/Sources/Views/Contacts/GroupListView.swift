import SwiftUI
import SwiftData

/// Gruppenliste und -verwaltung
struct GroupListView: View {
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGroup = false
    @State private var groupToDelete: ContactGroup?
    @State private var showDeleteConfirmation = false
    
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
    let group: ContactGroup
    
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
            }
        }
        .padding(.vertical, 4)
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
            
            Form {
                TextField("Gruppenname", text: $name)
                
                Stepper("Kontakt-Intervall: \(interval) Tage", value: $interval, in: 1...365)
                
                Stepper("Priorität: \(priority)", value: $priority, in: 0...100)
                
                Picker("Symbol", selection: $icon) {
                    ForEach(availableIcons, id: \.self) { iconName in
                        Label(iconName, systemImage: iconName).tag(iconName)
                    }
                }
            }
            .formStyle(.grouped)
            
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
    }
}
