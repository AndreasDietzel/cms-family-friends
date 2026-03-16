```
  ┌──────────────────────────────────────────────────────┐
  │                                                      │
  │    ██████╗ ███╗   ███╗ ███████╗                      │
  │   ██╔════╝ ████╗ ████║ ██╔════╝                      │
  │   ██║      ██╔████╔██║ ███████╗                      │
  │   ██║      ██║╚██╔╝██║ ╚════██║                      │
  │   ╚██████╗ ██║ ╚═╝ ██║ ███████║                      │
  │    ╚═════╝ ╚═╝     ╚═╝ ╚══════╝                      │
  │                                                      │
  │    F A M I L Y    &    F R I E N D S                  │
  │                                                      │
  ├──────────────────────────────────────────────────────┤
  │  Stay connected to the people who matter.   macOS 14+ │
  └──────────────────────────────────────────────────────┘
```

**Automatisches Kontakt-Tracking für macOS** – Bleib mit deiner Familie und deinen Freunden in Verbindung, ohne manuell etwas zu dokumentieren.

## 🎯 Was ist CMS Family & Friends?

CMS Family & Friends ist eine native macOS App, die automatisch deine Kommunikation mit wichtigen Menschen trackt. Statt manuell Einträge zu pflegen, gleicht die App automatisch mit deinem Kalender, Telefon, iMessage, WhatsApp, E-Mail und FaceTime ab.

**Das Ziel:** Du wirst proaktiv erinnert, wenn der Kontakt zu jemandem zu lange ausgesetzt war – basierend auf individuellen Intervallen pro Kontaktgruppe.

## ✨ Features

### Automatisches Tracking
| Datenquelle | API/Zugriff | Status |
|------------|-------------|--------|
| 📅 Kalender | EventKit | ✅ Implementiert |
| 📞 Telefon | CallHistory DB | ✅ Implementiert |
| 💬 iMessage | Messages SQLite DB | ✅ Implementiert |
| 📱 WhatsApp | WhatsApp SQLite DB | ✅ Implementiert |
| ✉️ E-Mail | Mail.app DB | ✅ Implementiert |
| 📹 FaceTime | Call History | ✅ Implementiert |
| 👤 Kontakte | Contacts Framework | ✅ Implementiert |

### Kontaktmanagement
- **Kontaktgruppen** mit individuellen Intervallen (z.B. Familie: 7 Tage, Freunde: 14 Tage)
- **Automatische Geburtstags-Erinnerungen**
- **Dynamische Kontaktpausen-Warnungen** basierend auf Gruppenkonfiguration
- **Urgency-Level** – visuelle Anzeige der Dringlichkeit

### UI
- Native macOS SwiftUI App
- Dashboard mit Übersicht
- Menüleisten-Icon für schnellen Zugriff
- Echtzeit-Sync im Hintergrund

## 🏗️ Architektur

```
 ┌─────────────────────────────────────────────────────────────┐
 │  CMSFamilyFriends                                          │
 ├──────────┬──────────────────────────────────────────────────┤
 │          │                                                  │
 │  App     │  Entry Point & App Lifecycle                     │
 │          │                                                  │
 ├──────────┼──────────────────────────────────────────────────┤
 │          │                                                  │
 │  Models  │  TrackedContact ─ Kontakt + Tracking-Metadaten   │
 │          │  ContactGroup ──── Gruppen mit Intervallen       │
 │          │  CommunicationEvent  Kommunikations-Events       │
 │          │                                                  │
 ├──────────┼──────────────────────────────────────────────────┤
 │          │                                                  │
 │  Views   │  Dashboard ──── Hauptübersicht                   │
 │          │  Contacts ───── Kontakt- & Gruppenlisten         │
 │          │  Settings ───── Einstellungen                    │
 │          │  Components ─── Wiederverwendbare UI-Bausteine   │
 │          │                                                  │
 ├──────────┼──────────────────────────────────────────────────┤
 │          │                                                  │
 │ Services │  Kalender · iMessage · WhatsApp · Mail · Telefon │
 │          │                                                  │
 ├──────────┼──────────────────────────────────────────────────┤
 │          │                                                  │
 │ Managers │  ContactManager ── Zentraler Sync-Manager        │
 │          │                                                  │
 ├──────────┼──────────────────────────────────────────────────┤
 │          │                                                  │
 │ Sonstige │  Extensions · Utilities · Assets · Resources     │
 │          │                                                  │
 └──────────┴──────────────────────────────────────────────────┘
```

## 🔒 Datenschutz

- **Alle Daten bleiben lokal** auf deinem Mac
- **iCloud Sync** für mehrere Geräte (optional)
- **Kein Server, keine Drittanbieter** – 100% Apple-Ökosystem
- Full Disk Access erforderlich für iMessage, WhatsApp, Anrufhistorie

## 🛠️ Technischer Stack

- **Sprache:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Datenbank:** SwiftData (Core Data successor)
- **Plattform:** macOS 14+ (Sonoma)
- **APIs:** EventKit, Contacts, SQLite3, UserNotifications

## 📋 Voraussetzungen

- macOS 14 (Sonoma) oder neuer
- Xcode 15+
- Full Disk Access (für iMessage, WhatsApp, Anrufhistorie)
- Kalender- und Kontakte-Berechtigung

## 🚀 Setup

1. Repository klonen:
   ```bash
   git clone <repository-url>
   ```

2. In Xcode öffnen:
   ```bash
   open Package.swift
   ```

3. Build & Run (⌘R)

4. In Systemeinstellungen: Full Disk Access für die App aktivieren

## 📅 Roadmap

### Phase 1 (MVP) ✅
- [x] Grundstruktur & Datenmodell
- [x] Kalender-Integration
- [x] Kontakte-Integration
- [x] iMessage-Tracking
- [x] WhatsApp-Tracking
- [x] Telefon-History
- [x] Mail-Tracking
- [x] Dashboard UI
- [x] Kontaktgruppen mit Intervallen
- [x] Geburtstags-Erinnerungen
- [x] Kontaktpausen-Warnungen

### Phase 2
- [x] FaceTime-Integration
- [ ] iCloud Sync
- [ ] Detaillierte Kontakt-Statistiken
- [ ] Export/Import
- [ ] Widgets

### Phase 3
- [ ] iOS Companion App
- [ ] Apple Watch Komplikation
- [ ] KI-basierte Kontaktempfehlungen
- [ ] Shortcuts-Integration

## 📄 Lizenz

Privates Projekt – Alle Rechte vorbehalten.
