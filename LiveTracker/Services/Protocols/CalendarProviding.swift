import Foundation
import EventKit

enum CalendarAccessStatus: Equatable {
    case notDetermined
    case denied
    case fullAccess
    case unavailable
}

struct CalendarShift: Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let breakStart: Date?
    let breakEnd: Date?
    let breakPaid: Bool
    let calendarEventID: String?
    let syncIdentifier: String
}

struct CalendarEventLink: Equatable, Sendable {
    let eventIdentifiers: String
    let syncIdentifier: String
}

@MainActor
protocol CalendarProviding {
    var authorizationStatus: CalendarAccessStatus { get }
    func requestAccess() async throws
    func save(_ shift: Shift) throws -> CalendarEventLink
    func fetchShifts(from start: Date, to end: Date) throws -> [CalendarShift]
    func delete(_ shift: Shift) throws
}
