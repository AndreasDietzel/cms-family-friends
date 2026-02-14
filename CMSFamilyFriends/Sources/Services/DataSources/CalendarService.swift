import Foundation
import EventKit

/// Service für Kalender-Integration (EventKit)
actor CalendarService {
    private let eventStore = EKEventStore()
    
    struct CalendarEvent {
        let identifier: String
        let title: String
        let startDate: Date
        let endDate: Date
        let attendees: [String]  // E-Mail-Adressen der Teilnehmer
        let location: String?
        let isAllDay: Bool
    }
    
    /// Berechtigung für Kalender-Zugriff anfordern
    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }
    
    /// Letzte Events abrufen (Standard: 90 Tage)
    func fetchRecentEvents(daysPast: Int = 90) async throws -> [CalendarEvent] {
        let granted = try await requestAccess()
        guard granted else {
            throw ServiceError.notAuthorized("Kalender-Zugriff nicht gewährt")
        }
        
        let startDate = Calendar.current.date(byAdding: .day, value: -daysPast, to: Date())!
        let endDate = Date()
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        
        let ekEvents = eventStore.events(matching: predicate)
        
        return ekEvents.compactMap { event in
            // Nur Events mit Teilnehmern (= Meetings/Treffen)
            let attendeeEmails = event.attendees?.compactMap { $0.url?.absoluteString
                .replacingOccurrences(of: "mailto:", with: "")
            } ?? []
            
            return CalendarEvent(
                identifier: event.eventIdentifier,
                title: event.title ?? "Kein Titel",
                startDate: event.startDate,
                endDate: event.endDate,
                attendees: attendeeEmails,
                location: event.location,
                isAllDay: event.isAllDay
            )
        }
    }
    
    /// Nur Events mit anderen Personen (Meetings/Treffen)
    func fetchMeetingEvents(daysPast: Int = 90) async throws -> [CalendarEvent] {
        let allEvents = try await fetchRecentEvents(daysPast: daysPast)
        return allEvents.filter { !$0.attendees.isEmpty }
    }
}
