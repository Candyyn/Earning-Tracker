import Foundation

protocol EarningsCalculating {
    func earningsForFullShift(_ shift: Shift, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double
    func earningsForActiveShift(_ shift: Shift, now: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double
    func workSegments(for shift: Shift, workedUntil: Date) -> [(Date, Date)]
    func earningsForSegment(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double
    func earningsForShift(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double
    func nextRateBoundary(after date: Date, calendar: Calendar) -> Date
    func currentType(for date: Date) -> ShiftType
    func hourlyRate(for date: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double
}
