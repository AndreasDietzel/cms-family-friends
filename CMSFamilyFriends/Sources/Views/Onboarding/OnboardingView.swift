import SwiftUI

/// Onboarding-View: Führt den Nutzer durch die Berechtigungsanfragen
struct OnboardingView: View {
    @EnvironmentObject var contactManager: ContactManager
    @EnvironmentObject var reminderManager: ReminderManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var currentStep = 0
    
    private let steps: [(title: String, description: String, icon: String)] = [
        (
            "Willkommen",
            "Diese App hilft dir, den Kontakt zu Familie und Freunden zu pflegen – automatisch und diskret.",
            "hand.wave.fill"
        ),
        (
            "Kontakte",
            "Zugriff auf deine Kontakte wird benötigt, um Geburtstage und Namen zu synchronisieren.",
            "person.crop.circle"
        ),
        (
            "Kalender",
            "Kalenderereignisse werden analysiert, um persönliche Treffen zu erkennen.",
            "calendar"
        ),
        (
            "Erinnerungen",
            "Überfällige Kontakte werden automatisch als Erinnerung in der Erinnerungen-App angelegt.",
            "bell.badge"
        ),
        (
            "Full Disk Access",
            "Für iMessage, WhatsApp und Anrufhistorie wird Full Disk Access benötigt. Du kannst dies jederzeit in den Systemeinstellungen aktivieren.",
            "lock.shield"
        ),
        (
            "Datenschutz",
            "Alle Daten bleiben auf deinem Gerät. Es werden keine Nachrichteninhalte gelesen – nur Zeitstempel und Absender/Empfänger. Kein Server, keine Drittanbieter.",
            "hand.raised.fill"
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
                .frame(maxWidth: 400)
            
            // Aktionsbuttons je nach Schritt
            if currentStep == 4 {
                Button("Full Disk Access öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
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
