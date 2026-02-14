import SwiftUI
import SwiftData

@main
struct CMSFamilyFriendsApp: App {
    @StateObject private var contactManager = ContactManager()
    @StateObject private var reminderManager = ReminderManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("keepInDock") private var keepInDock = true
    @State private var showOnboarding = false
    
    /// AppDelegate für Dock-Verhalten (Fenster schließen ohne App zu beenden)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
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
        MenuBarExtra("CMS Family & Friends", systemImage: "person.2.circle.fill") {
            MenuBarView()
                .environmentObject(contactManager)
        }
    }
}
