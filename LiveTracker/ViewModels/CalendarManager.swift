import EventKit
import Foundation

enum CalendarManagerError: LocalizedError {
    case accessDenied
    case calendarSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Enable calendar access in Settings to sync shifts."
        case .calendarSourceUnavailable:
            return "No writable calendar source is available for saving shifts."
        }
    }
}

final class CalendarManager: CalendarProviding {
    private let store = EKEventStore()
    
    init() {}

    private let calendarName = "Shifts"

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
            .first(where: { $0.title == calendarName }) {
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
    func save(_ shift: Shift) throws -> String {
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
                    existingEventIds.insert(event.eventIdentifier)
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
            if event.url == shiftURL && !existingEventIds.contains(event.eventIdentifier) {
                existingEvents.append(event)
                existingEventIds.insert(event.eventIdentifier)
            }
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
                targets.append(EventTarget(title: "Work Shift", start: shift.start, end: min(bStart, shift.end)))
            }
            if bStart < bEnd {
                targets.append(EventTarget(title: shift.breakPaid ? "Break (Paid)" : "Break (Unpaid)", start: bStart, end: bEnd))
            }
            if bEnd < shift.end {
                targets.append(EventTarget(title: "Work Shift", start: max(bEnd, shift.start), end: shift.end))
            }
        } else {
            targets.append(EventTarget(title: "Work Shift", start: shift.start, end: shift.end))
        }

        var finalEventIds: [String] = []

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
            finalEventIds.append(event.eventIdentifier)
        }
        
        // 5. Remove any excess events
        if existingEvents.count > targets.count {
            for i in targets.count..<existingEvents.count {
                try store.remove(existingEvents[i], span: .thisEvent, commit: false)
            }
        }

        try store.commit()
        return finalEventIds.joined(separator: ";")
    }

    // MARK: - Import calendar-only shifts
    func fetchShifts(from start: Date, to end: Date) throws -> [Shift] {
        let calendar = try shiftsCalendar()

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
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
        
        var fetchedShifts: [Shift] = []
        
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
                
                if event.title.contains("Break") {
                    bStart = event.startDate
                    bEnd = event.endDate
                    bPaid = event.title.contains("Paid")
                }
            }
            
            fetchedShifts.append(Shift(
                id: uuid,
                start: shiftStart,
                end: shiftEnd,
                breakStart: bStart,
                breakEnd: bEnd,
                breakPaid: bPaid,
                calendarEventId: first.eventIdentifier // Store one event ID for legacy/compatibility
            ))
        }
        
        // Process native Apple Calendar events
        for event in nativeEvents {
            // It's a single contiguous shift, no break.
            fetchedShifts.append(Shift(
                id: UUID(), // We generate a new UUID since it's native
                start: event.startDate,
                end: event.endDate,
                breakStart: nil,
                breakEnd: nil,
                breakPaid: false,
                calendarEventId: event.eventIdentifier
            ))
        }

        return fetchedShifts
    }
    
    // MARK: - Delete Shift
    func delete(_ shift: Shift) throws {
        let calendar = try shiftsCalendar()
        
        // 1. Delete by stored IDs first
        if let storedIds = shift.calendarEventId {
            let ids = storedIds.split(separator: ";").map(String.init)
            for id in ids {
                if let event = store.event(withIdentifier: id) {
                    try store.remove(event, span: .thisEvent, commit: false)
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
            if event.url == shiftURL {
                try store.remove(event, span: .thisEvent, commit: false)
            }
        }
        try store.commit()
    }
}
