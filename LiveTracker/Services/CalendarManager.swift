import EventKit
import Foundation

enum CalendarManagerError: LocalizedError {
    case accessDenied
    case calendarSourceUnavailable
    case eventIdentifierUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Kalenderåtkomst nekades. Aktivera kalenderåtkomst i Inställningar för att synka arbetspass."
        case .calendarSourceUnavailable:
            return "Det finns ingen skrivbar kalenderkälla att spara arbetspass i."
        case .eventIdentifierUnavailable:
            return "Kalendern returnerade inget id för det sparade arbetspasset."
        }
    }
}

final class CalendarManager: CalendarProviding {
    private let store = EKEventStore()
    private let calendarName = "Arbetspass"

    private enum EventTitle {
        static let work = "Arbetspass"
        static let paidBreak = "Rast (betald)"
        static let unpaidBreak = "Rast (obetald)"
    }

    init() {}

    var authorizationStatus: CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .fullAccess
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .unavailable
        }
    }

    // MARK: - Permission
    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        if !granted {
            throw CalendarManagerError.accessDenied
        }
    }

    // MARK: - Calendar
    private func shiftsCalendar() throws -> EKCalendar {
        if let calendar = store.calendars(for: .event)
            .first(where: { $0.title == calendarName && $0.allowsContentModifications }) {
            return calendar
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName
        guard let source = store.defaultCalendarForNewEvents?.source else {
            throw CalendarManagerError.calendarSourceUnavailable
        }
        calendar.source = source

        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
    
    private func shiftURL(for shift: Shift) -> URL? {
        return URL(string: "livetracker://shift/\(shift.id.uuidString)") ?? URL(string: "livetracker://")
    }

    // MARK: - Save / Update Shift
    func save(_ shift: Shift) throws -> CalendarEventLink {
        let calendar = try shiftsCalendar()
        let shiftURL = shiftURL(for: shift)
        
        var existingEvents: [EKEvent] = []
        var existingEventIds = Set<String>()
        
        // 1. Find existing events by stored IDs
        if let storedIds = shift.calendarEventId {
            let ids = storedIds.split(separator: ";").map(String.init)
            for id in ids {
                if let event = store.event(withIdentifier: id) {
                    existingEvents.append(event)
                    if let eventID = event.eventIdentifier {
                        existingEventIds.insert(eventID)
                    }
                }
            }
        }
        
        // 2. Find any missed events by URL fallback
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: shift.start) ?? shift.start
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: shift.end) ?? shift.end
        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )
        let fallbackEvents = store.events(matching: predicate)
        for event in fallbackEvents {
            guard event.url == shiftURL,
                  let eventID = event.eventIdentifier,
                  !existingEventIds.contains(eventID) else { continue }
            existingEvents.append(event)
            existingEventIds.insert(eventID)
        }
        
        // Sort existing events by start date to predictably map them
        existingEvents.sort { $0.startDate < $1.startDate }

        // 3. Determine target events
        struct EventTarget {
            let title: String
            let start: Date
            let end: Date
        }
        
        var targets: [EventTarget] = []
        if let bStart = shift.breakStart, let bEnd = shift.breakEnd {
            if shift.start < bStart {
                targets.append(EventTarget(title: EventTitle.work, start: shift.start, end: min(bStart, shift.end)))
            }
            if bStart < bEnd {
                targets.append(EventTarget(
                    title: shift.breakPaid ? EventTitle.paidBreak : EventTitle.unpaidBreak,
                    start: bStart,
                    end: bEnd
                ))
            }
            if bEnd < shift.end {
                targets.append(EventTarget(title: EventTitle.work, start: max(bEnd, shift.start), end: shift.end))
            }
        } else {
            targets.append(EventTarget(title: EventTitle.work, start: shift.start, end: shift.end))
        }

        var finalEvents: [EKEvent] = []

        // 4. Update or create events
        for (i, target) in targets.enumerated() {
            let event: EKEvent
            if i < existingEvents.count {
                event = existingEvents[i]
            } else {
                event = EKEvent(eventStore: store)
                event.calendar = calendar
            }
            
            event.title = target.title
            event.startDate = target.start
            event.endDate = target.end
            event.url = shiftURL
            
            try store.save(event, span: .thisEvent, commit: false)
            finalEvents.append(event)
        }
        
        // 5. Remove any excess events
        if existingEvents.count > targets.count {
            for i in targets.count..<existingEvents.count {
                try store.remove(existingEvents[i], span: .thisEvent, commit: false)
            }
        }

        try store.commit()
        let finalEventIDs = finalEvents.compactMap(\.eventIdentifier)
        guard finalEventIDs.count == finalEvents.count else {
            throw CalendarManagerError.eventIdentifierUnavailable
        }
        return CalendarEventLink(
            eventIdentifiers: finalEventIDs.joined(separator: ";"),
            syncIdentifier: syncIdentifier(for: shift.id)
        )
    }

    // MARK: - Import calendar-only shifts
    func fetchShifts(from start: Date, to end: Date) throws -> [CalendarShift] {
        let calendar = try shiftsCalendar()

        let paddedStart = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let paddedEnd = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        let predicate = store.predicateForEvents(
            withStart: paddedStart,
            end: paddedEnd,
            calendars: [calendar]
        )
        
        let allEvents = store.events(matching: predicate)
        
        // Group by URL (LiveTracker UUIDs)
        var groupedByUUID: [String: [EKEvent]] = [:]
        var nativeEvents: [EKEvent] = [] // Events created directly in Apple Calendar
        
        for event in allEvents {
            if let urlStr = event.url?.absoluteString, urlStr.hasPrefix("livetracker://shift/") {
                let uuidStr = urlStr.replacingOccurrences(of: "livetracker://shift/", with: "")
                groupedByUUID[uuidStr, default: []].append(event)
            } else {
                nativeEvents.append(event)
            }
        }
        
        var fetchedShifts: [CalendarShift] = []
        
        // Process grouped shifts
        for (uuidStr, events) in groupedByUUID {
            guard let uuid = UUID(uuidString: uuidStr), let first = events.first else { continue }
            
            var shiftStart: Date = first.startDate
            var shiftEnd: Date = first.endDate
            var bStart: Date? = nil
            var bEnd: Date? = nil
            var bPaid = false
            
            for event in events {
                if event.startDate < shiftStart { shiftStart = event.startDate }
                if event.endDate > shiftEnd { shiftEnd = event.endDate }
                
                if event.title == EventTitle.paidBreak || event.title == EventTitle.unpaidBreak {
                    bStart = event.startDate
                    bEnd = event.endDate
                    bPaid = event.title == EventTitle.paidBreak
                }
            }
            
            let eventIdentifiers = events
                .compactMap { $0.eventIdentifier }
                .joined(separator: ";")
            fetchedShifts.append(CalendarShift(
                id: uuid,
                start: shiftStart,
                end: shiftEnd,
                breakStart: bStart,
                breakEnd: bEnd,
                breakPaid: bPaid,
                calendarEventID: eventIdentifiers.isEmpty ? nil : eventIdentifiers,
                syncIdentifier: syncIdentifier(for: uuid)
            ))
        }
        
        // Process native Apple Calendar events
        for event in nativeEvents {
            // It's a single contiguous shift, no break.
            fetchedShifts.append(CalendarShift(
                id: UUID(), // We generate a new UUID since it's native
                start: event.startDate,
                end: event.endDate,
                breakStart: nil,
                breakEnd: nil,
                breakPaid: false,
                calendarEventID: event.eventIdentifier,
                syncIdentifier: syncIdentifier(for: event)
            ))
        }

        return fetchedShifts.filter { $0.end > start && $0.start < end }
    }
    
    // MARK: - Delete Shift
    func delete(_ shift: Shift) throws {
        let calendar = try shiftsCalendar()
        var removedEventIDs = Set<String>()
        
        // 1. Delete by stored IDs first
        if let storedIds = shift.calendarEventId {
            let ids = storedIds.split(separator: ";").map(String.init)
            for id in ids {
                if let event = store.event(withIdentifier: id) {
                    try store.remove(event, span: .thisEvent, commit: false)
                    removedEventIDs.insert(id)
                }
            }
        }
        
        // 2. Fallback to delete by URL
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: shift.start) ?? shift.start
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: shift.end) ?? shift.end
        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )
        let existingEvents = store.events(matching: predicate)
        let shiftURL = shiftURL(for: shift)
        
        for event in existingEvents {
            guard event.url == shiftURL else { continue }
            if let eventID = event.eventIdentifier,
               removedEventIDs.contains(eventID) {
                continue
            }
            try store.remove(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    private func syncIdentifier(for id: UUID) -> String {
        "livetracker:\(id.uuidString.lowercased())"
    }

    private func syncIdentifier(for event: EKEvent) -> String {
        let occurrence = event.occurrenceDate ?? event.startDate ?? .distantPast
        let externalIdentifier = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? "unknown"
        return "eventkit:\(externalIdentifier):\(occurrence.timeIntervalSinceReferenceDate)"
    }
}
