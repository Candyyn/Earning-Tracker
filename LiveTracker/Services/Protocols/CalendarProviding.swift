import Foundation
import EventKit

protocol CalendarProviding {
    func requestAccess() async throws
    func save(_ shift: Shift) throws -> String
    func fetchShifts(from start: Date, to end: Date) throws -> [Shift]
    func delete(_ shift: Shift) throws
}
