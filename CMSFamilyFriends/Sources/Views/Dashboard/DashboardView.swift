import SwiftUI
import SwiftData

/// Dashboard-Hauptansicht mit Übersicht aller Kontakte
struct DashboardView: View {
    @EnvironmentObject var contactManager: ContactManager
    @Query(sort: \TrackedContact.lastContactDate, order: .forward)
    private var overdueContacts: [TrackedContact]
    
    @Query private var allGroups: [ContactGroup]
    @Query(sort: \ContactReminder.dueDate)
    private var upcomingReminders: [ContactReminder]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header mit Sync-Status
                headerSection
                
                // Überfällige Kontakte
                overdueSection
                
                // Anstehende Geburtstage
                birthdaySection
                
                // Gruppenübersicht
                groupOverviewSection
                
                // Letzte Aktivitäten
                recentActivitySection
            }
            .padding()
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Willkommen zurück!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if let lastSync = contactManager.lastSyncDate {
                    Text("Letzter Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            Spacer()
            
            // Sync Button
            Button(action: {
                Task { await contactManager.performSync() }
            }) {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            
            // Status-Indikator
            Circle()
                .fill(contactManager.isTracking ? .green : .red)
                .frame(width: 10, height: 10)
        }
    }
    
    // MARK: - Überfällige Kontakte
    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Überfällige Kontakte", systemImage: "exclamationmark.triangle.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            
            let overdue = overdueContacts.filter(\.isOverdue)
            
            if overdue.isEmpty {
                ContentUnavailableView(
                    "Alles up to date!",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Keine überfälligen Kontakte.")
                )
                .frame(height: 120)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 250))
                ], spacing: 12) {
                    ForEach(overdue, id: \.id) { contact in
                        ContactCardView(contact: contact)
                    }
                }
            }
        }
        .padding()
        .background(.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Geburtstage
    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Anstehende Geburtstage", systemImage: "gift.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            
            let upcoming = overdueContacts
                .filter { $0.daysUntilBirthday != nil && $0.daysUntilBirthday! <= 30 }
                .sorted { ($0.daysUntilBirthday ?? 999) < ($1.daysUntilBirthday ?? 999) }
            
            if upcoming.isEmpty {
                Text("Keine Geburtstage in den nächsten 30 Tagen")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming, id: \.id) { contact in
                    HStack {
                        Text("🎂")
                        Text(contact.fullName)
                            .fontWeight(.medium)
                        Spacer()
                        if let days = contact.daysUntilBirthday {
                            Text(days == 0 ? "Heute!" : "in \(days) Tagen")
                                .foregroundStyle(days <= 3 ? .red : .secondary)
                                .fontWeight(days <= 3 ? .bold : .regular)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Gruppenübersicht
    private var groupOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gruppen", systemImage: "person.3.fill")
                .font(.title2)
                .fontWeight(.semibold)
            
            if allGroups.isEmpty {
                Text("Noch keine Gruppen angelegt")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200))
                ], spacing: 12) {
                    ForEach(allGroups, id: \.id) { group in
                        GroupCardView(group: group)
                    }
                }
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Letzte Aktivitäten
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Letzte Aktivitäten", systemImage: "clock.fill")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Wird nach dem ersten Sync angezeigt...")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Contact Card
struct ContactCardView: View {
    let contact: TrackedContact
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(urgencyColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(contact.firstName.prefix(1))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName)
                    .fontWeight(.semibold)
                
                if let days = contact.daysSinceLastContact {
                    Text("Letzter Kontakt vor \(days) Tagen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let group = contact.group {
                    Text(group.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Urgency Indicator
            if contact.isOverdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }
    
    private var urgencyColor: Color {
        let level = contact.urgencyLevel
        switch level {
        case 0..<0.5: return .green
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .orange
        default: return .red
        }
    }
}

// MARK: - Group Card
struct GroupCardView: View {
    let group: ContactGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: group.icon)
                    .font(.title2)
                Text(group.name)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(group.contacts.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            HStack {
                Text("Intervall: \(group.contactIntervalDays) Tage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if group.overdueCount > 0 {
                    Text("\(group.overdueCount) überfällig")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }
}
