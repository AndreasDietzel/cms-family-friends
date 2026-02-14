import SwiftUI

/// Einstellungsansicht
struct SettingsView: View {
    @AppStorage("syncIntervalMinutes") private var syncInterval = 30
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("enableBirthdayReminders") private var enableBirthdayReminders = true
    @AppStorage("birthdayReminderDays") private var birthdayReminderDays = 3
    @AppStorage("enableMenuBar") private var enableMenuBar = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    @EnvironmentObject var reminderManager: ReminderManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Einstellungen")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Allgemein
                settingsSection("Allgemein", icon: "gear") {
                    Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    Toggle("Menüleisten-Symbol", isOn: $enableMenuBar)
                    
                    HStack {
                        Text("Sync-Intervall")
                        Spacer()
                        Picker("", selection: $syncInterval) {
                            Text("15 Minuten").tag(15)
                            Text("30 Minuten").tag(30)
                            Text("1 Stunde").tag(60)
                            Text("2 Stunden").tag(120)
                        }
                        .frame(width: 200)
                    }
                }
                
                // Benachrichtigungen
                settingsSection("Benachrichtigungen", icon: "bell") {
                    Toggle("Desktop-Benachrichtigungen", isOn: $enableNotifications)
                    Toggle("Geburtstags-Erinnerungen", isOn: $enableBirthdayReminders)
                    
                    if enableBirthdayReminders {
                        Stepper(
                            "\(birthdayReminderDays) Tage vorher erinnern",
                            value: $birthdayReminderDays,
                            in: 1...14
                        )
                    }
                }
                
                // Reminders Integration
                settingsSection("Erinnerungen-App", icon: "list.bullet") {
                    HStack {
                        Text("Status")
                        Spacer()
                        if reminderManager.isAuthorized {
                            Label("Verbunden", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Zugriff gewähren") {
                                Task { await reminderManager.requestAccess() }
                            }
                        }
                    }
                    
                    if reminderManager.reminderListExists {
                        Label("Liste 'CMS Family & Friends' aktiv", systemImage: "list.bullet.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                
                // Datenquellen-Status
                settingsSection("Datenquellen", icon: "tray.2") {
                    dataSourceRow("Kalender", icon: "calendar", status: .connected)
                    dataSourceRow("Kontakte", icon: "person.crop.circle", status: .connected)
                    dataSourceRow("iMessage", icon: "message", status: .needsAccess)
                    dataSourceRow("WhatsApp", icon: "bubble.left", status: .checking)
                    dataSourceRow("Telefon", icon: "phone", status: .needsAccess)
                    dataSourceRow("FaceTime", icon: "video", status: .checking)
                    dataSourceRow("Mail", icon: "envelope", status: .needsAccess)
                }
                
                // Datenschutz
                settingsSection("Datenschutz & Sicherheit", icon: "lock.shield") {
                    Text("Alle Daten werden lokal gespeichert und über iCloud synchronisiert. Keine Drittanbieter-Server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Full Disk Access öffnen") {
                        // Öffne Systemeinstellungen
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Views
    
    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    enum DataSourceStatus {
        case connected, needsAccess, checking, unavailable
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .needsAccess: return .orange
            case .checking: return .yellow
            case .unavailable: return .red
            }
        }
        
        var label: String {
            switch self {
            case .connected: return "Verbunden"
            case .needsAccess: return "Zugriff nötig"
            case .checking: return "Prüfe..."
            case .unavailable: return "Nicht verfügbar"
            }
        }
    }
    
    private func dataSourceRow(_ name: String, icon: String, status: DataSourceStatus) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(name)
            Spacer()
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(status.color)
        }
    }
}
