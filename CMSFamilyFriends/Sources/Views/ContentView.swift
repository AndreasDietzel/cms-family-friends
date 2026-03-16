import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var contactManager: ContactManager
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: SidebarTab = .dashboard
    @State private var selectedGroup: ContactGroup?
    @State private var searchText = ""
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab, selectedGroup: $selectedGroup)
        } detail: {
            switch selectedTab {
            case .settings:
                SettingsView()
            default:
                if let group = selectedGroup {
                    ContactListView(searchText: $searchText, filterGroup: group)
                        .id(group.id)
                } else {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView()
                    case .contacts:
                        ContactListView(searchText: $searchText)
                    case .groups:
                        GroupListView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Kontakte durchsuchen...")
        .navigationTitle(selectedGroup?.name ?? selectedTab.title)
        .onAppear {
            contactManager.modelContext = modelContext
            contactManager.startTracking()
        }
        .safeAreaInset(edge: .bottom) {
            // Sync-Fehler Banner
            if !contactManager.syncErrors.isEmpty {
                syncErrorBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
    case settings = "Einstellungen"
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .contacts: return "person.2"
        case .groups: return "person.3"
        case .settings: return "gear"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @Binding var selectedGroup: ContactGroup?
    @EnvironmentObject var contactManager: ContactManager
    @Query(sort: \ContactGroup.priority, order: .reverse) private var groups: [ContactGroup]
    
    var body: some View {
        List(selection: $selectedTab) {
            Section {
                Label(SidebarTab.dashboard.title, systemImage: SidebarTab.dashboard.icon)
                    .tag(SidebarTab.dashboard)
                
                Label(SidebarTab.contacts.title, systemImage: SidebarTab.contacts.icon)
                    .tag(SidebarTab.contacts)
                
                Label(SidebarTab.groups.title, systemImage: SidebarTab.groups.icon)
                    .tag(SidebarTab.groups)
            }
            
            if !groups.isEmpty {
                Section("Gruppen") {
                    ForEach(groups, id: \.id) { group in
                        Button {
                            selectedGroup = group
                            selectedTab = .contacts
                        } label: {
                            HStack {
                                Image(systemName: group.icon)
                                    .foregroundStyle(Color(hex: group.colorHex) ?? .blue)
                                    .frame(width: 20)
                                Text(group.name)
                                Spacer()
                                if group.overdueCount > 0 {
                                    Text("\(group.overdueCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.red)
                                        .clipShape(Capsule())
                                } else {
                                    Text("\(group.contacts.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
            
            Section {
                Label(SidebarTab.settings.title, systemImage: SidebarTab.settings.icon)
                    .tag(SidebarTab.settings)
                    .badge(contactManager.syncErrors.count)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .onChange(of: selectedTab) { _, _ in
            selectedGroup = nil
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
}
