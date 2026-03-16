import SwiftUI
import SwiftData
import SQLite3

@main
struct CMSFamilyFriendsApp: App {
    @StateObject private var contactManager = ContactManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("keepInDock") private var keepInDock = true
    @State private var showOnboarding = false
    
    /// AppDelegate für Dock-Verhalten (Fenster schließen ohne App zu beenden)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let modelContainer: ModelContainer
    
    init() {
        // Datenbank vor SwiftData bereinigen (ContactReminder entfernen)
        Self.migrateRemoveReminders()
        
        do {
            let schema = Schema([
                TrackedContact.self,
                ContactGroup.self,
                CommunicationEvent.self
            ])
            let appSupport = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CMSFamilyFriends")
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let config = ModelConfiguration(
                "CMSFamilyFriends",
                schema: schema,
                url: appSupport.appendingPathComponent("CMSFamilyFriends.store")
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }
    
    /// Entfernt die ZCONTACTREMINDER-Tabelle aus der SQLite-Datenbank, bevor SwiftData sie öffnet
    private static func migrateRemoveReminders() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("CMSFamilyFriends")
        let dbPath = dbDir.appendingPathComponent("CMSFamilyFriends.store").path
        
        guard FileManager.default.fileExists(atPath: dbPath) else { return }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        // Prüfen ob die Tabelle noch existiert
        var stmt: OpaquePointer?
        let checkSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='ZCONTACTREMINDER'"
        guard sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        let hasTable = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)
        
        guard hasTable else { return } // Bereits migriert
        
        let migrations = [
            "DROP TABLE IF EXISTS ZCONTACTREMINDER",
            "DELETE FROM Z_PRIMARYKEY WHERE Z_NAME = 'ContactReminder'",
            "DELETE FROM Z_MODELCACHE",
            "DELETE FROM Z_METADATA",
        ]
        
        for sql in migrations {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(contactManager)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                }
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    }
                    appDelegate.keepInDock = keepInDock
                }
                .onChange(of: keepInDock) { _, newValue in
                    appDelegate.keepInDock = newValue
                }
        }
        .modelContainer(modelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        
        // Menubar Extra für schnellen Zugriff
        MenuBarExtra("CMS Family & Friends", systemImage: "person.2.circle.fill") {
            MenuBarView()
                .environmentObject(contactManager)
        }
    }
}
