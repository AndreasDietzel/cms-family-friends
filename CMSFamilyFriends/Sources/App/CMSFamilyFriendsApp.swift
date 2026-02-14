import SwiftUI
import SwiftData
import os.log

@main
struct CMSFamilyFriendsApp: App {
    @StateObject private var contactManager = ContactManager()
    @StateObject private var reminderManager = ReminderManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("keepInDock") private var keepInDock = true
    @AppStorage("enableMenuBar") private var enableMenuBar = true
    @State private var showOnboarding = false
    
    /// AppDelegate für Dock-Verhalten (Fenster schließen ohne App zu beenden)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CMSFamilyFriends", category: "App")
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(contactManager)
                .environmentObject(reminderManager)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                }
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    }
                    appDelegate.keepInDock = keepInDock
                    
                    // Debug: Bundle-Identität prüfen
                    let bundleId = Bundle.main.bundleIdentifier ?? "nil"
                    Self.logger.info("Bundle ID: \(bundleId, privacy: .public)")
                    Self.logger.info("Bundle path: \(Bundle.main.bundlePath, privacy: .public)")
                    Self.logger.info("MenuBar enabled: \(self.enableMenuBar, privacy: .public)")
                }
                .onChange(of: keepInDock) { _, newValue in
                    appDelegate.keepInDock = newValue
                }
        }
        .modelContainer(for: [
            TrackedContact.self,
            ContactGroup.self,
            CommunicationEvent.self,
            ContactReminder.self
        ])
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        
        // Menubar Extra für schnellen Zugriff
        MenuBarExtra("CMS Family & Friends", systemImage: "person.2.circle.fill", isInserted: $enableMenuBar) {
            MenuBarView()
                .environmentObject(contactManager)
        }
        .menuBarExtraStyle(.window)
    }
}
