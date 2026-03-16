import AppKit

/// AppDelegate für Dock-Verhalten:
/// Wenn "Im Dock behalten" aktiv ist, wird die App beim Schließen des Fensters
/// NICHT beendet, sondern läuft im Hintergrund weiter (wie z.B. Spotify oder Slack).
/// Ein Klick auf das Dock-Symbol öffnet das Fenster wieder.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wird von CMSFamilyFriendsApp gesetzt
    var keepInDock = true
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // false = App läuft weiter wenn Fenster geschlossen wird
        // true  = App beendet sich wenn letztes Fenster zu ist
        return !keepInDock
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Wenn Dock-Icon geklickt wird und kein Fenster offen ist → Fenster wieder öffnen
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Fenster öffnen", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        return menu
    }
    
    @objc private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
