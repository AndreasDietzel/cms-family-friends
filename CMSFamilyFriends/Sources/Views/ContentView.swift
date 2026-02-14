import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var contactManager: ContactManager
    @Environment(\.modelContext) private var modelContext
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
            contactManager.modelContext = modelContext
            contactManager.startTracking()
        }
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
