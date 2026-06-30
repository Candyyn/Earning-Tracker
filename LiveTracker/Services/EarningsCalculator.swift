import Foundation

struct WorkSegment: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct EarningsBreakdown: Equatable, Sendable {
    var grossPay: Decimal = 0
    var vacationPay: Decimal = 0
    var estimatedWithheldTax: Decimal = 0
    var netPay: Decimal = 0

    var taxableGross: Decimal { grossPay + vacationPay }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            grossPay: lhs.grossPay + rhs.grossPay,
            vacationPay: lhs.vacationPay + rhs.vacationPay,
            estimatedWithheldTax: lhs.estimatedWithheldTax + rhs.estimatedWithheldTax,
            netPay: lhs.netPay + rhs.netPay
        )
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}

struct HoursByShiftType: Equatable {
    var day: Double = 0
    var evening: Double = 0
    var night: Double = 0
    var weekend: Double = 0
    var holiday: Double = 0
    var holidayMajor: Double = 0

    var total: Double {
        day + evening + night + weekend + holiday + holidayMajor
    }

    mutating func add(hours: Double, for type: ShiftType) {
        switch type {
        case .day: day += hours
        case .evening: evening += hours
        case .night: night += hours
        case .weekend: weekend += hours
        case .holiday: holiday += hours
        case .holidayMajor: holidayMajor += hours
        }
    }
}

struct RateSchedule {
    static let standard = RateSchedule(dayStartHour: 8, eveningStartHour: 18)

    let dayStartHour: Int
    let eveningStartHour: Int

    func shiftType(for date: Date, calendar: Calendar, holidays: [HolidayDates]) -> ShiftType {
        if holidays.contains(where: { $0.isTierB(date: date, calendar: calendar) }) {
            return .holidayMajor
        }
        if holidays.contains(where: { $0.isTierA(date: date, calendar: calendar) }) {
            return .holiday
        }

        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return .weekend
        }

        let hour = calendar.component(.hour, from: date)
        if hour >= dayStartHour && hour < eveningStartHour {
            return .day
        } else if hour >= eveningStartHour {
            return .evening
        } else {
            return .night
        }
    }

    func nextBoundary(after date: Date, calendar: Calendar, holidayBoundaries: [Date]) -> Date {
        let timeBoundaries = [
            nextTimeBoundary(after: date, hour: dayStartHour, calendar: calendar),
            nextTimeBoundary(after: date, hour: eveningStartHour, calendar: calendar),
            calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
        ].compactMap { $0 }

        let candidates = timeBoundaries + holidayBoundaries.filter { $0 > date }
        return candidates.min() ?? date.addingTimeInterval(60 * 60)
    }

    private func nextTimeBoundary(after date: Date, hour: Int, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }
}

final class EarningsCalculator: EarningsCalculating {
    private let holidayService: HolidayProviding
    private let schedule: RateSchedule
    
    init(holidayService: HolidayProviding, schedule: RateSchedule = .standard) {
        self.holidayService = holidayService
        self.schedule = schedule
    }
    
    func earningsForFullShift(_ shift: Shift, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal {
        breakdownForFullShift(shift, calendar: calendar, paySettingsProvider: paySettingsProvider).netPay
    }

    func earningsForActiveShift(_ shift: Shift, now: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal {
        let workedUntil = min(now, shift.end)
        let segments = workSegments(for: shift, workedUntil: workedUntil)
        var total: Decimal = 0
        for segment in segments {
            total += earningsForSegment(from: segment.start, to: segment.end, calendar: calendar, paySettingsProvider: paySettingsProvider)
        }
        return total
    }

    func workSegments(for shift: Shift, workedUntil: Date) -> [WorkSegment] {
        let effectiveEnd = min(max(workedUntil, shift.start), shift.end)
        guard shift.start < effectiveEnd else { return [] }

        if let bStart = shift.breakStart,
           let bEnd = shift.breakEnd,
           bStart < bEnd,
           !shift.breakPaid {
            var segments: [WorkSegment] = []
            let breakStart = min(max(bStart, shift.start), effectiveEnd)
            let breakEnd = min(max(bEnd, shift.start), effectiveEnd)

            if shift.start < breakStart {
                segments.append(WorkSegment(start: shift.start, end: breakStart))
            }
            if breakEnd < effectiveEnd {
                segments.append(WorkSegment(start: breakEnd, end: effectiveEnd))
            }
            return segments.filter { $0.start < $0.end }
        }
        return [WorkSegment(start: shift.start, end: effectiveEnd)]
    }

    func nextRateBoundary(after date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        let holidays = holidayService.cachedHolidays(for: year, calendar: calendar)
        let nextYearHolidays = holidayService.cachedHolidays(for: year + 1, calendar: calendar)
        let previousYearHolidays = holidayService.cachedHolidays(for: year - 1, calendar: calendar)

        let holidayBoundaries = [
            holidays,
            nextYearHolidays,
            previousYearHolidays
        ]
        .flatMap { $0.allBoundaries }

        return schedule.nextBoundary(after: date, calendar: calendar, holidayBoundaries: holidayBoundaries)
    }

    func earningsForSegment(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Decimal {
        breakdownForSegment(from: start, to: end, calendar: calendar, paySettingsProvider: paySettingsProvider).netPay
    }

    func breakdownForFullShift(
        _ shift: Shift,
        calendar: Calendar,
        paySettingsProvider: (Date) -> PaySettings?
    ) -> EarningsBreakdown {
        workSegments(for: shift, workedUntil: shift.end).reduce(into: EarningsBreakdown()) { total, segment in
            total += breakdownForSegment(
                from: segment.start,
                to: segment.end,
                calendar: calendar,
                paySettingsProvider: paySettingsProvider
            )
        }
    }

    func breakdownForSegment(
        from start: Date,
        to end: Date,
        calendar: Calendar,
        paySettingsProvider: (Date) -> PaySettings?
    ) -> EarningsBreakdown {
        guard start < end else { return EarningsBreakdown() }

        var result = EarningsBreakdown()
        var currentTime = start

        while currentTime < end {
            let boundary = nextRateBoundary(after: currentTime, calendar: calendar)
            let segmentEnd = min(end, boundary)
            let hours = segmentEnd.timeIntervalSince(currentTime) / 3600

            if let settings = paySettingsProvider(currentTime) {
                let type = currentType(for: currentTime, calendar: calendar)
                let rate = settings.rateBreakdown(for: type)
                result.grossPay += rate.grossPay.multiplied(by: hours)
                result.vacationPay += rate.vacationPay.multiplied(by: hours)
                result.estimatedWithheldTax += rate.estimatedWithheldTax.multiplied(by: hours)
                result.netPay += rate.netPay.multiplied(by: hours)
            }

            currentTime = segmentEnd
        }
        return result
    }
    
    func earningsForShift(from start: Date, to end: Date, calendar: Calendar = .current, paySettingsProvider: (Date) -> PaySettings?) -> Decimal {
        earningsForSegment(from: start, to: end, calendar: calendar, paySettingsProvider: paySettingsProvider)
    }

    func hourlyRate(for date: Date, calendar: Calendar = .current, paySettingsProvider: (Date) -> PaySettings?) -> Decimal {
        guard let selectedPay = paySettingsProvider(date) else { return 0 }

        let year = calendar.component(.year, from: date)

        let holidays = holidayDates(around: year, calendar: calendar)
        switch schedule.shiftType(for: date, calendar: calendar, holidays: holidays) {
        case .holidayMajor:
            return selectedPay.holidayRateB
        case .holiday:
            return selectedPay.holidayRateA
        case .weekend:
            return selectedPay.weekendRate
        case .day:
            return selectedPay.dayRate
        case .evening:
            return selectedPay.eveningRate
        case .night:
            return selectedPay.nightRate
        }
    }
    
    func currentType(for date: Date, calendar: Calendar = .current) -> ShiftType {
        let year = calendar.component(.year, from: date)
        let holidays = holidayDates(around: year, calendar: calendar)
        return schedule.shiftType(for: date, calendar: calendar, holidays: holidays)
    }

    private func holidayDates(around year: Int, calendar: Calendar) -> [HolidayDates] {
        [year - 1, year, year + 1].map {
            holidayService.cachedHolidays(for: $0, calendar: calendar)
        }
    }
}
