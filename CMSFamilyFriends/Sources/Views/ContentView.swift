import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var contactManager: ContactManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("toolbarIconStyle") private var toolbarIconStyle = "blackGray"
    @State private var selectedTab: SidebarTab = .dashboard
    
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
        .navigationTitle(selectedTab.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AppToolbarIcon()
                    .id(toolbarIconStyle)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await contactManager.performSync() }
                }) {
                    if contactManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Jetzt synchronisieren")
                .disabled(contactManager.isSyncing)
            }
            ToolbarItem(placement: .automatic) {
                Circle()
                    .fill(contactManager.isTracking ? .green : .red)
                    .frame(width: 8, height: 8)
                    .help(contactManager.isTracking ? "Tracking aktiv" : "Tracking inaktiv")
            }
        }
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

/// Verfügbare Toolbar-Icon-Stile
enum ToolbarIconStyle: String, CaseIterable, Identifiable {
    case blackGray = "blackGray"
    case gradient = "gradient"
    case monochrome = "monochrome"
    case colorful = "colorful"
    case minimal = "minimal"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .blackGray: return "Schwarz"
        case .gradient: return "Gradient"
        case .monochrome: return "Mono"
        case .colorful: return "Bunt"
        case .minimal: return "Minimal"
        }
    }
    
    /// SF Symbol für die Menüleiste passend zum Stil
    var menuBarSymbol: String {
        switch self {
        case .blackGray: return "person.2.fill"
        case .gradient: return "person.2.circle.fill"
        case .monochrome: return "person.2"
        case .colorful: return "person.2.circle.fill"
        case .minimal: return "person.2"
        }
    }
}

/// Menüleisten-Icon (SF Symbol) das sich per Einstellung anpasst
struct MenuBarIcon: View {
    var styleName: String
    
    private var activeStyle: ToolbarIconStyle {
        ToolbarIconStyle(rawValue: styleName) ?? .blackGray
    }
    
    var body: some View {
        Image(systemName: activeStyle.menuBarSymbol)
    }
}

/// Toolbar-Icon das sich per Einstellung anpassen lässt
struct AppToolbarIcon: View {
    @AppStorage("toolbarIconStyle") private var selectedStyle = "blackGray"
    var style: ToolbarIconStyle? = nil
    
    private var activeStyle: ToolbarIconStyle {
        style ?? (ToolbarIconStyle(rawValue: selectedStyle) ?? .blackGray)
    }
    
    var body: some View {
        ZStack {
            background
            symbol
        }
        .frame(width: 26, height: 26)
        .help("CMS Family & Friends")
    }
    
    @ViewBuilder
    private var background: some View {
        switch activeStyle {
        case .blackGray:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
        case .gradient:
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.3, blue: 0.8), Color(red: 0.6, green: 0.2, blue: 0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .monochrome:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
        case .colorful:
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [.orange, .pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .minimal:
            Color.clear
        }
    }
    
    @ViewBuilder
    private var symbol: some View {
        switch activeStyle {
        case .blackGray:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.gray)
        case .gradient, .colorful:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .monochrome:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        case .minimal:
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
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
