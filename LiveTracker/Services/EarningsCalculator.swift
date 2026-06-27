import Foundation

class EarningsCalculator: EarningsCalculating {
    private let holidayService: HolidayProviding
    
    init(holidayService: HolidayProviding) {
        self.holidayService = holidayService
    }
    
    func earningsForFullShift(_ shift: Shift, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double {
        let segments = workSegments(for: shift, workedUntil: shift.end)
        var total: Double = 0
        for (segStart, segEnd) in segments {
            total += earningsForSegment(from: segStart, to: segEnd, calendar: calendar, paySettingsProvider: paySettingsProvider)
        }
        return total
    }

    func earningsForActiveShift(_ shift: Shift, now: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double {
        let workedUntil = min(now, shift.end)
        let segments = workSegments(for: shift, workedUntil: workedUntil)
        var total: Double = 0
        for (segStart, segEnd) in segments {
            total += earningsForSegment(from: segStart, to: segEnd, calendar: calendar, paySettingsProvider: paySettingsProvider)
        }
        return total
    }

    func workSegments(for shift: Shift, workedUntil: Date) -> [(Date, Date)] {
        if let bStart = shift.breakStart, let bEnd = shift.breakEnd, !shift.breakPaid {
            var segs: [(Date, Date)] = []
            if shift.start < bStart {
                segs.append((shift.start, min(bStart, workedUntil)))
            }
            if workedUntil > bEnd {
                segs.append((max(bEnd, shift.start), workedUntil))
            }
            return segs
        }
        return [(shift.start, workedUntil)]
    }

    func nextRateBoundary(after date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        let holidays = holidayService.cachedHolidays(for: year, calendar: calendar)
        let nextYearHolidays = holidayService.cachedHolidays(for: year + 1, calendar: calendar)
        let previousYearHolidays = holidayService.cachedHolidays(for: year - 1, calendar: calendar)

        let rateBoundaries = [
            nextTimeBoundary(after: date, hour: 8, calendar: calendar),
            nextTimeBoundary(after: date, hour: 18, calendar: calendar),
            calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
        ].compactMap { $0 }

        let holidayBoundaries = [
            holidays,
            nextYearHolidays,
            previousYearHolidays
        ]
        .flatMap { $0.allBoundaries }
        .filter { $0 > date }

        return (rateBoundaries + holidayBoundaries).min() ?? date.addingTimeInterval(60 * 60)
    }

    private func nextTimeBoundary(after date: Date, hour: Int, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    func earningsForSegment(from start: Date, to end: Date, calendar: Calendar, paySettingsProvider: (Date) -> PaySettings?) -> Double {
        var earnings: Double = 0
        var currentTime = start

        while currentTime < end {
            let rate = hourlyRate(for: currentTime, calendar: calendar, paySettingsProvider: paySettingsProvider)
            let boundary = nextRateBoundary(after: currentTime, calendar: calendar)
            let segmentEnd = min(end, boundary)

            let seconds = segmentEnd.timeIntervalSince(currentTime)
            earnings += (seconds / 3600.0) * rate

            currentTime = segmentEnd
        }
        return earnings
    }
    
    func earningsForShift(from start: Date, to end: Date, calendar: Calendar = .current, paySettingsProvider: (Date) -> PaySettings?) -> Double {
        earningsForSegment(from: start, to: end, calendar: calendar, paySettingsProvider: paySettingsProvider)
    }

    func hourlyRate(for date: Date, calendar: Calendar = .current, paySettingsProvider: (Date) -> PaySettings?) -> Double {
        guard let selectedPay = paySettingsProvider(date) else { return 0 }

        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let year = calendar.component(.year, from: date)

        let holidays = holidayService.cachedHolidays(for: year, calendar: calendar)

        if holidays.isTierB(date: date, calendar: calendar) {
            return selectedPay.holidayRateB
        }
        if holidays.isTierA(date: date, calendar: calendar) {
            return selectedPay.holidayRateA
        }

        if weekday == 1 || weekday == 7 {
            return selectedPay.weekendRate
        }

        if hour >= 8 && hour < 18 {
            return selectedPay.dayRate
        } else if hour >= 18 && hour < 24 {
            return selectedPay.eveningRate
        } else {
            return selectedPay.nightRate
        }
    }
    
    func currentType(for date: Date) -> ShiftType {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let year = calendar.component(.year, from: date)

        let holidays = holidayService.cachedHolidays(for: year, calendar: calendar)

        if holidays.isTierB(date: date, calendar: calendar) {
            return .holidayMajor
        }
        if holidays.isTierA(date: date, calendar: calendar) {
            return .holiday
        }
        if weekday == 1 || weekday == 7 {
            return .weekend
        }
        if hour >= 8 && hour < 18 {
            return .day
        } else if hour >= 18 && hour < 24 {
            return .evening
        } else {
            return .night
        }
    }
}
