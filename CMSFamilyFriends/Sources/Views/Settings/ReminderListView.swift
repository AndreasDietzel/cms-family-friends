import SwiftUI
import SwiftData

/// Ansicht für Erinnerungen
struct ReminderListView: View {
    @EnvironmentObject var reminderManager: ReminderManager
    @Query(sort: \ContactReminder.dueDate) private var reminders: [ContactReminder]
    
    @State private var filter: ReminderFilter = .active
    
    enum ReminderFilter: String, CaseIterable {
        case active = "Aktiv"
        case overdue = "Überfällig"
        case snoozed = "Zurückgestellt"
        case completed = "Erledigt"
    }
    
    var filteredReminders: [ContactReminder] {
        switch filter {
        case .active:
            return reminders.filter { !$0.isCompleted && !$0.isSnoozed }
        case .overdue:
            return reminders.filter { $0.isOverdue }
        case .snoozed:
            return reminders.filter { $0.isSnoozed }
        case .completed:
            return reminders.filter { $0.isCompleted }
        }
    }
    
    var body: some View {
        VStack {
            // Filter-Leiste
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(ReminderFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
                
                Spacer()
                
                // Reminders-Sync Status
                if reminderManager.isAuthorized {
                    Label("Reminders verbunden", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Reminders verbinden") {
                        Task { await reminderManager.requestAccess() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            
            // Erinnerungsliste
            List(filteredReminders, id: \.id) { reminder in
                ReminderRowView(reminder: reminder)
            }
            
            if filteredReminders.isEmpty {
                ContentUnavailableView(
                    "Keine Erinnerungen",
                    systemImage: "bell.slash",
                    description: Text("Keine \(filter.rawValue.lowercased())en Erinnerungen vorhanden.")
                )
            }
        }
    }
}

struct ReminderRowView: View {
    @Environment(\.modelContext) private var modelContext
    let reminder: ContactReminder
    
    var body: some View {
        HStack(spacing: 12) {
            // Typ-Icon
            Image(systemName: reminder.type.icon)
                .font(.title2)
                .foregroundStyle(typeColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .fontWeight(.medium)
                    .strikethrough(reminder.isCompleted)
                
                if let contact = reminder.contact {
                    Text(contact.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let note = reminder.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let dueDate = reminder.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(reminder.isOverdue ? .red : .secondary)
                        .fontWeight(reminder.isOverdue ? .bold : .regular)
                }
                
                if reminder.isSnoozed, let until = reminder.snoozedUntil {
                    Text("Bis \(until.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            
            // Aktionen
            if !reminder.isCompleted {
                Menu {
                    Button("Erledigt") {
                        reminder.complete()
                    }
                    
                    Menu("Zurückstellen") {
                        Button("1 Tag") { reminder.snooze(days: 1) }
                        Button("3 Tage") { reminder.snooze(days: 3) }
                        Button("1 Woche") { reminder.snooze(days: 7) }
                        Button("2 Wochen") { reminder.snooze(days: 14) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.vertical, 4)
        .opacity(reminder.isCompleted ? 0.5 : 1.0)
    }
    
    private var typeColor: Color {
        switch reminder.type {
        case .contactPause: return .red
        case .birthday: return .orange
        case .followUp: return .blue
        case .custom: return .purple
        }
    }
}
