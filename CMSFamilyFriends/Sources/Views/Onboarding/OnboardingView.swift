import SwiftUI
import SwiftData

/// Vereinfachtes Onboarding – 3 Schritte statt 6
struct OnboardingView: View {
    @EnvironmentObject var contactManager: ContactManager
    @EnvironmentObject var reminderManager: ReminderManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var currentStep = 0
    @State private var createDefaultGroups = true
    
    private let steps: [(title: String, description: String, icon: String)] = [
        (
            "Willkommen bei CMS",
            "Pflege den Kontakt zu Familie und Freunden – automatisch und diskret. Alle Daten bleiben auf deinem Gerät. Es werden keine Nachrichteninhalte gelesen.",
            "hand.wave.fill"
        ),
        (
            "Berechtigungen",
            "Die App benötigt Zugriff auf Kontakte, Kalender und Erinnerungen.\n\nFür iMessage, WhatsApp und Anrufhistorie wird zusätzlich Full Disk Access benötigt – das kannst du jederzeit in den Einstellungen konfigurieren.",
            "lock.shield.fill"
        ),
        (
            "Fertig!",
            "Du kannst jetzt Kontakte importieren, Gruppen erstellen und persönliche Treffen mit einem Klick dokumentieren.\n\nTipp: Rechtsklick auf einen Kontakt → \"Treffen dokumentieren\"",
            "checkmark.circle.fill"
        )
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? .blue : .gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Content
            let step = steps[currentStep]
            
            Image(systemName: step.icon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            
            Text(step.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(step.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            // Berechtigungen-Schritt: FDA-Button
            if currentStep == 1 {
                Button("Full Disk Access öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Letzter Schritt: Standard-Gruppen
            if currentStep == 2 {
                Toggle("Standard-Gruppen erstellen (Familie, Freunde, etc.)", isOn: $createDefaultGroups)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: 400)
            }
            
            Spacer()
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Zurück") {
                        withAnimation { currentStep -= 1 }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }
                
                Spacer()
                
                if currentStep < steps.count - 1 {
                    Button("Weiter") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                } else {
                    Button("Los geht's!") {
                        if createDefaultGroups {
                            for defaults in ContactGroup.defaultGroups {
                                let group = ContactGroup(
                                    name: defaults.name,
                                    icon: defaults.icon,
                                    colorHex: defaults.color,
                                    contactIntervalDays: defaults.interval,
                                    priority: defaults.priority
                                )
                                modelContext.insert(group)
                            }
                            try? modelContext.save()
                        }
                        hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(40)
        .frame(width: 550, height: 450)
    }
}
