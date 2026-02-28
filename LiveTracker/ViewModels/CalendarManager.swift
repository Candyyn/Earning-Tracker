import EventKit

final class CalendarManager {
    static let shared = CalendarManager()
    private let store = EKEventStore()

    private let calendarName = "Shifts"

    // MARK: - Permission
    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        if !granted {
            throw NSError(domain: "Calendar", code: 1)
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
        calendar.source = store.defaultCalendarForNewEvents?.source

        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    // MARK: - Save / Update Shift
    func save(_ shift: Shift) throws -> String {
        let calendar = try shiftsCalendar()

        let event: EKEvent
        if let id = shift.calendarEventId,
           let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }

        event.title = "Work Shift"
        event.startDate = shift.start
        event.endDate = shift.end

        // Store break info in notes
        if let bStart = shift.breakStart,
           let bEnd = shift.breakEnd {
            event.notes =
            """
            Break: \(bStart.formatted(date: .omitted, time: .shortened))
            – \(bEnd.formatted(date: .omitted, time: .shortened))
            \(shift.breakPaid ? "(Paid)" : "(Unpaid)")
            """
        } else {
            event.notes = nil
        }

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Import calendar-only shifts
    func fetchShifts(from start: Date, to end: Date) throws -> [Shift] {
        let calendar = try shiftsCalendar()

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [calendar]
        )

        return store.events(matching: predicate).map { event in
            Shift(
                start: event.startDate,
                end: event.endDate,
                breakPaid: false,
                calendarEventId: event.eventIdentifier
            )
        }
    }
}
