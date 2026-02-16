import SwiftUI
import SwiftData
import Contacts
import EventKit

/// Vereinfachtes Onboarding – 3 Schritte statt 6
struct OnboardingView: View {
    @EnvironmentObject var contactManager: ContactManager
    @EnvironmentObject var reminderManager: ReminderManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var currentStep = 0
    @State private var createDefaultGroups = true
    @State private var contactsGranted = false
    @State private var calendarGranted = false
    @State private var remindersGranted = false
    
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
            
            // Berechtigungen-Schritt: Einzelne Berechtigung anfordern
            if currentStep == 1 {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: contactsGranted ? "checkmark.circle.fill" : "person.crop.circle")
                            .foregroundStyle(contactsGranted ? .green : .secondary)
                        Text("Kontakte")
                        Spacer()
                        if contactsGranted {
                            Text("Erlaubt").foregroundStyle(.green).font(.caption)
                        } else {
                            Button("Erlauben") {
                                Task {
                                    let store = CNContactStore()
                                    contactsGranted = (try? await store.requestAccess(for: .contacts)) ?? false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    HStack {
                        Image(systemName: calendarGranted ? "checkmark.circle.fill" : "calendar")
                            .foregroundStyle(calendarGranted ? .green : .secondary)
                        Text("Kalender")
                        Spacer()
                        if calendarGranted {
                            Text("Erlaubt").foregroundStyle(.green).font(.caption)
                        } else {
                            Button("Erlauben") {
                                Task {
                                    let store = EKEventStore()
                                    calendarGranted = (try? await store.requestFullAccessToEvents()) ?? false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    HStack {
                        Image(systemName: remindersGranted ? "checkmark.circle.fill" : "bell")
                            .foregroundStyle(remindersGranted ? .green : .secondary)
                        Text("Erinnerungen")
                        Spacer()
                        if remindersGranted {
                            Text("Erlaubt").foregroundStyle(.green).font(.caption)
                        } else {
                            Button("Erlauben") {
                                Task {
                                    let store = EKEventStore()
                                    remindersGranted = (try? await store.requestFullAccessToReminders()) ?? false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.secondary)
                        Text("Full Disk Access")
                        Spacer()
                        Button("Öffnen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Für iMessage, WhatsApp & Anrufliste")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 350)
                .onAppear {
                    // Aktuellen Status prüfen
                    contactsGranted = CNContactStore.authorizationStatus(for: .contacts) == .authorized
                    calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                    remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
                }
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
