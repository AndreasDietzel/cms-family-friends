import SwiftUI
import SwiftData

@main
struct CMSFamilyFriendsApp: App {
    @StateObject private var contactManager = ContactManager()
    @StateObject private var reminderManager = ReminderManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(contactManager)
                .environmentObject(reminderManager)
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
