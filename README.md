# CMS Family & Friends

```
     _____ __  __ ____
    / ____|  \/  / ___|
   | |    | \  / \___ \    _____ _   _ _ _  _ _  _   ___
   | |    | |\/| |___) |  |  ___| \ | |_  )(_) || | / __|
   | |____| |  | |____/   | |_  |  \| | / /  \ || | \__ \
    \_____|_|  |_|         |_|   |_|\__|/___|  \__/  |___/
                 .__     .        .
                 |__  _ *|  _  _  _| _
                 |  |(_< | (/_(/_(_|_>
   ──────────────────────────────────────────────────────
   Stay connected to the people who matter.    macOS 14+
   ──────────────────────────────────────────────────────
```

**Automatic contact tracking for macOS** – Stay in touch with the people who matter, without manually logging anything.

## What is CMS Family & Friends?

CMS Family & Friends is a native macOS app that automatically tracks your communication with important people. Instead of maintaining manual records, the app syncs with your Calendar, Phone, iMessage, WhatsApp, Email, and FaceTime.

**The Goal:** Get proactive reminders when you haven't been in touch with someone for too long – based on individually configurable intervals per contact group.

## Features

### Automatic Communication Tracking
| Data Source | Access Method | Status |
|-------------|---------------|--------|
| Calendar | EventKit | ✅ Implemented |
| Phone Calls | CallHistory SQLite DB | ✅ Implemented |
| iMessage | Messages SQLite DB | ✅ Implemented |
| WhatsApp | WhatsApp SQLite DB | ✅ Implemented |
| Email | Mail.app SQLite DB | ✅ Implemented |
| FaceTime | CallHistory SQLite DB | ✅ Implemented |
| Contacts | Contacts Framework | ✅ Implemented |

### Contact Management
- **Contact groups** with individual intervals (e.g., Family: 7 days, Friends: 14 days, Acquaintances: 90 days)
- **Default groups:** Family, Relatives, Close Friends, Friends, Neighbors, Acquaintances, Work
- **Custom groups** with configurable interval, priority, and icon
- **Manual real-life meeting tracking** – log in-person meetings with a single click
- **Automatic birthday reminders**
- **Dynamic overdue warnings** based on group configuration
- **Urgency level** – visual indicator of how urgently someone needs to be contacted
- **Batch assignment** of unassigned contacts to groups

### Reminders (Apple Reminders Integration)
- Dedicated "CMS Family & Friends" reminders list
- Automatic reminders when contact has lapsed
- Priority based on contact importance
- Snooze/postpone reminders
- Auto-complete after successful contact

### Privacy by Design
- **All data stays local** on your Mac – no server, no third parties
- **No message content is read** – only metadata (sender, date, direction)
- 100% Apple ecosystem

### UI
- Native macOS SwiftUI app
- Dashboard with overview of overdue contacts, upcoming birthdays, recent activity
- Menu bar icon for quick access
- Background sync at configurable intervals
- Onboarding flow for initial setup
- Dock persistence – app keeps running when window is closed

## Architecture

```
CMSFamilyFriends/
├── Sources/
│   ├── App/                    # App entry point & AppDelegate
│   ├── Models/                 # SwiftData models
│   │   ├── TrackedContact      # Contact with tracking metadata
│   │   ├── ContactGroup        # Groups with intervals & priorities
│   │   ├── CommunicationEvent  # Individual communication events
│   │   ├── ContactReminder     # Reminders
│   │   └── DataSource          # Data source status tracking
│   ├── Views/                  # SwiftUI views
│   │   ├── Dashboard/          # Main overview
│   │   ├── Contacts/           # Contact lists, groups, import
│   │   ├── Settings/           # Settings & reminder management
│   │   ├── Onboarding/         # First-run setup
│   │   └── Components/         # Reusable UI components
│   ├── Services/               # Data source services
│   │   └── DataSources/        # Calendar, iMessage, WhatsApp, etc.
│   ├── Managers/               # Business logic
│   │   ├── ContactManager      # Central sync manager with deduplication
│   │   └── ReminderManager     # Apple Reminders integration
│   ├── Extensions/             # Swift extensions
│   └── Utilities/              # Logging, data export
├── Assets.xcassets/            # App icons & assets
└── Resources/                  # Info.plist & resources
```

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Persistence:** SwiftData
- **Platform:** macOS 14+ (Sonoma)
- **APIs:** EventKit, Contacts Framework, SQLite3, UserNotifications

## Requirements

- macOS 14 (Sonoma) or later
- Swift toolchain (via Xcode or standalone Swift installation)
- Full Disk Access (required for iMessage, WhatsApp, Phone/FaceTime call history, Mail)
- Calendar and Contacts permissions

## Getting Started

### Option A: Build & Run without Xcode

```bash
git clone https://github.com/AndreasDietzel/cms-family-friends.git
cd cms-family-friends

# Build and run directly
make run

# Or create a proper .app bundle
make app
open CMSFamilyFriends.app

# Install to /Applications
make install
```

### Option B: Open in Xcode

```bash
git clone https://github.com/AndreasDietzel/cms-family-friends.git
cd cms-family-friends
open Package.swift
# Build & Run (Cmd+R)
```

### Permissions Setup

1. **Calendar & Contacts** – the app will prompt automatically on first launch
2. **Full Disk Access** – enable manually in System Settings → Privacy & Security → Full Disk Access
3. **Reminders** – optional, for Apple Reminders integration

## Roadmap

### Phase 1 (MVP) ✅
- [x] Data model & core architecture
- [x] Calendar integration (EventKit)
- [x] Contacts integration (Contacts Framework)
- [x] iMessage tracking (SQLite)
- [x] WhatsApp tracking (SQLite)
- [x] Phone call history (SQLite)
- [x] FaceTime tracking (SQLite)
- [x] Email tracking (Mail.app SQLite)
- [x] Apple Reminders integration
- [x] Dashboard UI
- [x] Contact groups with intervals
- [x] Birthday reminders
- [x] Overdue contact warnings
- [x] Menu bar extra
- [x] Real-life meeting tracking
- [x] Contact import from macOS Contacts
- [x] Batch group assignment
- [x] Persistent data storage (SwiftData)
- [x] Working search bar
- [x] Editable settings with live effect
- [x] Standalone build without Xcode (Makefile)
- [x] Group creation & default groups in onboarding
- [x] Future-date bug fix for last contact display

### Phase 2
- [ ] iCloud Sync
- [ ] Detailed contact statistics & charts
- [ ] CSV/JSON export & import
- [ ] macOS Widgets

### Phase 3
- [ ] iOS Companion App
- [ ] Apple Watch complication
- [ ] AI-based contact recommendations
- [ ] Shortcuts integration

## License

MIT License – see [LICENSE](LICENSE) for details.
