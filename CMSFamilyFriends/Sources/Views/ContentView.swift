import SwiftUI

struct ContentView: View {
    @EnvironmentObject var contactManager: ContactManager
    @State private var selectedTab: SidebarTab = .dashboard
    @State private var searchText = ""
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .contacts:
                ContactListView(searchText: $searchText)
            case .groups:
                GroupListView()
            case .reminders:
                ReminderListView()
            case .settings:
                SettingsView()
            }
        }
        .searchable(text: $searchText, prompt: "Kontakte durchsuchen...")
        .navigationTitle(selectedTab.title)
        .onAppear {
            contactManager.startTracking()
        }
        .overlay(alignment: .top) {
            // Sync-Fehler Banner
            if !contactManager.syncErrors.isEmpty {
                syncErrorBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: contactManager.syncErrors.isEmpty)
    }
    
    // MARK: - Sync Error Banner
    private var syncErrorBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("\(contactManager.syncErrors.count) Datenquelle(n) mit Fehlern")
                .font(.caption)
            Spacer()
            Button("Details") {
                selectedTab = .settings
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

enum SidebarTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case contacts = "Kontakte"
    case groups = "Gruppen"
    case reminders = "Erinnerungen"
    case settings = "Einstellungen"
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .contacts: return "person.2"
        case .groups: return "person.3"
        case .reminders: return "bell"
        case .settings: return "gear"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @EnvironmentObject var contactManager: ContactManager
    
    var body: some View {
        List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
                .badge(badgeCount(for: tab))
                .accessibilityLabel("\(tab.title)\(badgeCount(for: tab) > 0 ? ", \(badgeCount(for: tab)) Einträge" : "")")
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
    
    private func badgeCount(for tab: SidebarTab) -> Int {
        switch tab {
        case .settings:
            return contactManager.syncErrors.count
        default:
            return 0
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var contactManager: ContactManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Überfällige Kontakte")
                .font(.headline)
            
            Divider()
            
            if contactManager.isSyncing {
                Label("Synchronisiere...", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Keine überfälligen Kontakte")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            
            Divider()

            if let url = URL(string: "cmsfamilyfriends://open") {
                Button("CMS öffnen") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 250)
    }
}

#Preview {
    ContentView()
        .environmentObject(ContactManager())
        .environmentObject(ReminderManager())
}
