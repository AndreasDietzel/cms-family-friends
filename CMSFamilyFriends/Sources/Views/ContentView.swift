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
                ContactListView()
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
    
    var body: some View {
        List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var contactManager: ContactManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Überfällige Kontakte")
                .font(.headline)
            
            Divider()
            
            Text("Keine überfälligen Kontakte")
                .foregroundStyle(.secondary)
                .font(.caption)
            
            Divider()
            
            Button("CMS öffnen") {
                NSWorkspace.shared.open(URL(string: "cmsfamilyfriends://open")!)
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
