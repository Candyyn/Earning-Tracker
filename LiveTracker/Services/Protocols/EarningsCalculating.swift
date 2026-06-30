import Foundation

protocol EarningsCalculating {
    func earningsForFullShift(_ shift: Shift, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal
    func breakdownForFullShift(_ shift: Shift, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> EarningsBreakdown
    func earningsForActiveShift(_ shift: Shift, now: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal
    func workSegments(for shift: Shift, workedUntil: Date) -> [WorkSegment]
    func earningsForSegment(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal
    func breakdownForSegment(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> EarningsBreakdown
    func earningsForShift(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal
    func nextRateBoundary(after date: Date, calendar: Calendar) -> Date
    func currentType(for date: Date, calendar: Calendar) -> ShiftType
    func hourlyRate(for date: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal
}
