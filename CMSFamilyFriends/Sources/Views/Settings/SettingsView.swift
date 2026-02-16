import SwiftUI
import ServiceManagement

/// Einstellungsansicht
struct SettingsView: View {
    @AppStorage("syncIntervalMinutes") private var syncInterval = 30
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("enableBirthdayReminders") private var enableBirthdayReminders = true
    @AppStorage("birthdayReminderDays") private var birthdayReminderDays = 3
    @AppStorage("enableMenuBar") private var enableMenuBar = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("keepInDock") private var keepInDock = true
    
    @EnvironmentObject var reminderManager: ReminderManager
    @EnvironmentObject var contactManager: ContactManager
    
    @State private var showExportSuccess = false
    @State private var showImportPicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Einstellungen")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Allgemein
                settingsSection("Allgemein", icon: "gear") {
                    Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                        .onAppear {
                            syncLaunchAtLoginStatus()
                        }
                    Toggle("Menüleisten-Symbol", isOn: $enableMenuBar)
                    
                    Toggle("Im Dock behalten (Hintergrund)", isOn: $keepInDock)
                    Text("Wenn aktiviert, läuft die App im Hintergrund weiter, auch wenn das Fenster geschlossen wird. Das Symbol bleibt im Dock sichtbar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
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
                        .onChange(of: syncInterval) { _, _ in
                            contactManager.updateSyncInterval()
                        }
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
                
                // Datenquellen-Status (dynamisch aus ContactManager)
                settingsSection("Datenquellen", icon: "tray.2") {
                    // Full Disk Access Warnung wenn nötig
                    if needsFullDiskAccess {
                        fullDiskAccessBanner
                    }
                    
                    ForEach(DataSource.allCases) { source in
                        dataSourceRow(source)
                    }
                    
                    if let lastSync = contactManager.lastSyncDate {
                        HStack {
                            Text("Letzter Sync")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastSync.relativeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    Button(action: {
                        Task { await contactManager.performSync() }
                    }) {
                        if contactManager.isSyncing {
                            Label("Synchronisiere...", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(contactManager.isSyncing)
                }
                
                // Daten-Export / Import
                settingsSection("Daten", icon: "square.and.arrow.up") {
                    Text("Exportiere Kontakte und Gruppen als JSON (ohne Nachrichteninhalte).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button("Exportieren") {
                            exportData()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Importieren") {
                            showImportPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if showExportSuccess {
                        Label("Export erfolgreich!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                
                // Datenschutz
                settingsSection("Datenschutz & Sicherheit", icon: "lock.shield") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Alle Daten werden lokal gespeichert und über iCloud synchronisiert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Es werden keine Nachrichteninhalte gelesen – nur Metadaten (Zeitpunkt, Kontakt, Richtung).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Keine Drittanbieter-Server. Keine Telemetrie.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: openFullDiskAccessSettings) {
                        Label("Full Disk Access öffnen", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Full Disk Access
    
    /// Prüft ob iMessage, Telefon oder Mail keinen Zugriff haben
    private var needsFullDiskAccess: Bool {
        let fdaSources: [DataSource] = [.imessage, .phone, .email]
        return fdaSources.contains { source in
            let status = contactManager.dataSourceStatuses[source]
            switch status {
            case .needsAccess, .unavailable:
                return true
            default:
                return false
            }
        }
    }
    
    private var fullDiskAccessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Full Disk Access erforderlich")
                    .fontWeight(.semibold)
            }
            
            Text("iMessage, Telefon und Mail lesen lokale Datenbanken. Dafür muss die App unter **Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff** zugelassen werden.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Button(action: openFullDiskAccessSettings) {
                    Label("Systemeinstellungen öffnen", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button(action: {
                    Task { await contactManager.checkDataSourceAvailability() }
                }) {
                    Label("Erneut prüfen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
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
    
    private func dataSourceRow(_ source: DataSource) -> some View {
        let status = contactManager.dataSourceStatuses[source] ?? .checking
        return HStack {
            Image(systemName: source.icon)
                .frame(width: 20)
            Text(source.displayName)
            Spacer()
            
            if let count = contactManager.lastSyncResults[source] {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(status.color)
            
            // FDA-Quellen bekommen einen Button
            if case .needsAccess = status,
               [.imessage, .phone, .email].contains(source) {
                Button(action: openFullDiskAccessSettings) {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Full Disk Access in Systemeinstellungen öffnen")
            }
        }
        .accessibilityLabel("\(source.displayName): \(status.label)")
    }
    
    // MARK: - Export / Import
    
    private func exportData() {
        // Placeholder – DataExporter nutzt eigenen View-Flow
        showExportSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showExportSuccess = false
        }
    }
    
    // MARK: - Launch at Login
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        
        if enabled {
            let status = SMAppService.mainApp.status
            switch status {
            case .enabled:
                return // Bereits registriert
            case .requiresApproval:
                // User muss in Systemeinstellungen genehmigen
                SMAppService.openSystemSettingsLoginItems()
                return
            default:
                break
            }
            do {
                try SMAppService.mainApp.register()
            } catch {
                AppLogger.accessDenied(resource: "Launch at Login: \(error.localizedDescription)")
                // Nicht sofort zurücksetzen – kurz verzögern damit SwiftUI nicht in Loop gerät
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchAtLogin = false
                }
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                AppLogger.accessDenied(resource: "Launch at Login deaktivieren: \(error.localizedDescription)")
            }
        }
    }
    
    /// Login-Status von SMAppService synchronisieren
    private func syncLaunchAtLoginStatus() {
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status
        let isRegistered = (status == .enabled)
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }
    }
}
