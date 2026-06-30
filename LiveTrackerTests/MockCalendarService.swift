import Foundation
@testable import LiveTracker

@MainActor
final class MockCalendarService: CalendarProviding {
    var authorizationStatus: CalendarAccessStatus
    var requestError: Error?
    var saveError: Error?
    var fetchedShifts: [CalendarShift] = []
    private(set) var saveCallCount = 0
    private(set) var deleteCallCount = 0

    init(authorizationStatus: CalendarAccessStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAccess() async throws {
        if let requestError { throw requestError }
        authorizationStatus = .fullAccess
    }

    func save(_ shift: Shift) throws -> CalendarEventLink {
        saveCallCount += 1
        if let saveError { throw saveError }
        return CalendarEventLink(
            eventIdentifiers: "mock-event-\(shift.id.uuidString)",
            syncIdentifier: "livetracker:\(shift.id.uuidString.lowercased())"
        )
    }

    func fetchShifts(from start: Date, to end: Date) throws -> [CalendarShift] {
        fetchedShifts
    }

    func delete(_ shift: Shift) throws {
        deleteCallCount += 1
    }
}
