import AppKit

/// AppDelegate für Dock-Verhalten:
/// Wenn "Im Dock behalten" aktiv ist, wird die App beim Schließen des Fensters
/// NICHT beendet, sondern läuft im Hintergrund weiter (wie z.B. Spotify oder Slack).
/// Ein Klick auf das Dock-Symbol öffnet das Fenster wieder.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wird von CMSFamilyFriendsApp gesetzt
    var keepInDock = true
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Programmatisches App-Icon setzen (kein Asset Catalog nötig)
        NSApplication.shared.applicationIconImage = Self.generateAppIcon()
    }
    
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
    
    // MARK: - Programmatisches App-Icon
    
    /// Generiert ein cooles App-Icon mit Gradient und Personen-Symbol
    static func generateAppIcon() -> NSImage {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        
        image.lockFocus()
        
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        
        // Abgerundetes Quadrat (macOS Icon Shape)
        let cornerRadius: CGFloat = size * 0.22
        let iconPath = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Gradient Hintergrund: Tiefblau → Lila → Warmrosa
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(red: 0.15, green: 0.25, blue: 0.75, alpha: 1.0), 0.0),
            (NSColor(red: 0.45, green: 0.20, blue: 0.80, alpha: 1.0), 0.5),
            (NSColor(red: 0.85, green: 0.30, blue: 0.55, alpha: 1.0), 1.0)
        )
        gradient?.draw(in: iconPath, angle: -45)
        
        // Subtiler innerer Schein
        let innerRect = rect.insetBy(dx: 16, dy: 16)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius - 8, yRadius: cornerRadius - 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        innerPath.fill()
        
        // Herz-Form im Hintergrund (leicht transparent)
        let heartSize: CGFloat = size * 0.55
        let heartX = (size - heartSize) / 2
        let heartY = size * 0.18
        drawHeart(in: NSRect(x: heartX, y: heartY, width: heartSize, height: heartSize), alpha: 0.15)
        
        // Personen-Symbol (zwei Köpfe) – zentriert
        let personColor = NSColor.white
        
        // Linke Person
        let leftCenterX = size * 0.38
        let headY = size * 0.60
        let headRadius: CGFloat = size * 0.075
        
        personColor.withAlphaComponent(0.95).setFill()
        let leftHead = NSBezierPath(ovalIn: NSRect(
            x: leftCenterX - headRadius,
            y: headY - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        leftHead.fill()
        
        // Linker Körper
        let leftBody = NSBezierPath(ovalIn: NSRect(
            x: leftCenterX - headRadius * 1.6,
            y: headY - headRadius * 4.2,
            width: headRadius * 3.2,
            height: headRadius * 3.0
        ))
        leftBody.fill()
        
        // Rechte Person
        let rightCenterX = size * 0.62
        let rightHead = NSBezierPath(ovalIn: NSRect(
            x: rightCenterX - headRadius,
            y: headY - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        rightHead.fill()
        
        // Rechter Körper
        let rightBody = NSBezierPath(ovalIn: NSRect(
            x: rightCenterX - headRadius * 1.6,
            y: headY - headRadius * 4.2,
            width: headRadius * 3.2,
            height: headRadius * 3.0
        ))
        rightBody.fill()
        
        // Kleines Herz zwischen den Personen (oben)
        let miniHeartSize: CGFloat = size * 0.12
        drawHeart(
            in: NSRect(x: (size - miniHeartSize) / 2, y: size * 0.66, width: miniHeartSize, height: miniHeartSize),
            alpha: 0.9,
            color: NSColor(red: 1.0, green: 0.4, blue: 0.5, alpha: 1.0)
        )
        
        // "CMS" Text unten
        let textFont = NSFont.systemFont(ofSize: size * 0.10, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let text = "CMS"
        let textSize = text.size(withAttributes: textAttributes)
        let textPoint = NSPoint(x: (size - textSize.width) / 2, y: size * 0.12)
        text.draw(at: textPoint, withAttributes: textAttributes)
        
        image.unlockFocus()
        return image
    }
    
    /// Zeichnet eine Herz-Form
    private static func drawHeart(in rect: NSRect, alpha: CGFloat, color: NSColor = .white) {
        let path = NSBezierPath()
        let w = rect.width
        let h = rect.height
        let x = rect.origin.x
        let y = rect.origin.y
        
        // Herz aus zwei Bögen + Spitze
        path.move(to: NSPoint(x: x + w / 2, y: y + h * 0.25))
        
        // Linke Hälfte
        path.curve(to: NSPoint(x: x, y: y + h * 0.65),
                    controlPoint1: NSPoint(x: x + w * 0.1, y: y),
                    controlPoint2: NSPoint(x: x, y: y + h * 0.35))
        path.curve(to: NSPoint(x: x + w / 2, y: y + h),
                    controlPoint1: NSPoint(x: x, y: y + h * 0.85),
                    controlPoint2: NSPoint(x: x + w * 0.25, y: y + h))
        
        // Rechte Hälfte
        path.curve(to: NSPoint(x: x + w, y: y + h * 0.65),
                    controlPoint1: NSPoint(x: x + w * 0.75, y: y + h),
                    controlPoint2: NSPoint(x: x + w, y: y + h * 0.85))
        path.curve(to: NSPoint(x: x + w / 2, y: y + h * 0.25),
                    controlPoint1: NSPoint(x: x + w, y: y + h * 0.35),
                    controlPoint2: NSPoint(x: x + w * 0.9, y: y))
        
        path.close()
        color.withAlphaComponent(alpha).setFill()
        path.fill()
    }
    
    // MARK: - Launch at Login (LaunchAgent)
    
    /// LaunchAgent-Pfad für "Beim Anmelden starten"
    static var launchAgentPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.cmsfamilyfriends.app.plist")
    }
    
    /// Registriert/deregistriert die App für Autostart via LaunchAgent
    static func setLaunchAtLogin(_ enabled: Bool) {
        let plistPath = launchAgentPath
        
        if enabled {
            // Aktuellen App-Pfad ermitteln
            let appPath = Bundle.main.bundlePath
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.cmsfamilyfriends.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>open</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            
            do {
                try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.accessDenied(resource: "LaunchAgent erstellen: \(error.localizedDescription)")
            }
        } else {
            try? FileManager.default.removeItem(at: plistPath)
        }
    }
    
    /// Prüft ob LaunchAgent existiert
    static var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath.path)
    }
}
