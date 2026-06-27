import Foundation

struct HolidayDates {
    let tierARanges: [(start: Date, end: Date)]
    let tierBRanges: [(start: Date, end: Date)]

    init(tierARanges: [(start: Date, end: Date)], tierBRanges: [(start: Date, end: Date)]) {
        self.tierARanges = tierARanges
        self.tierBRanges = tierBRanges
    }

    init(year: Int, calendar: Calendar) {
        let easter = Self.easterSunday(year: year)

        let tierADays: [Date] = [
            Self.makeDate(year: year, month: 1, day: 6, calendar: calendar),
            Self.ascensionDay(year: year, calendar: calendar),
            Self.makeDate(year: year, month: 5, day: 1, calendar: calendar),
            Self.allSaintsDay(year: year, calendar: calendar),
            Self.makeDate(year: year, month: 6, day: 6, calendar: calendar),
        ]
        
        tierARanges = tierADays.map { holiday in
            let periodStart = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: holiday) ?? holiday
            let periodEnd = calendar.startOfDay(
                for: Self.nextWeekday(after: holiday, calendar: calendar)
            )
            return (periodStart, periodEnd)
        }

        var bRanges: [(Date, Date)] = []

        // Maundy Thursday → after Easter Monday
        let maundyThursday = calendar.date(byAdding: .day, value: -3, to: easter) ?? easter
        let easterMonday   = calendar.date(byAdding: .day, value: 1, to: easter) ?? easter
        bRanges.append((
            calendar.date(bySettingHour: 18, minute: 0, second: 0, of: maundyThursday) ?? maundyThursday,
            calendar.startOfDay(for: Self.nextWeekday(after: easterMonday, calendar: calendar))
        ))

        // Whitsun Eve → after Pentecost
        let pentecost  = calendar.date(byAdding: .day, value: 49, to: easter) ?? easter
        let whitsunEve = calendar.date(byAdding: .day, value: -1, to: pentecost) ?? pentecost
        bRanges.append((
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: whitsunEve) ?? whitsunEve,
            calendar.startOfDay(for: Self.nextWeekday(after: pentecost, calendar: calendar))
        ))

        // Midsummer Eve → after Midsummer Day
        let midsummerEve = Self.midsummerEve(year: year, calendar: calendar)
        let midsummerDay = calendar.date(byAdding: .day, value: 1, to: midsummerEve) ?? midsummerEve
        bRanges.append((
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: midsummerEve) ?? midsummerEve,
            calendar.startOfDay(for: Self.nextWeekday(after: midsummerDay, calendar: calendar))
        ))

        // Christmas Eve → after Boxing Day
        let christmasEve = Self.makeDate(year: year, month: 12, day: 24, calendar: calendar)
        let boxingDay    = Self.makeDate(year: year, month: 12, day: 26, calendar: calendar)
        bRanges.append((
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: christmasEve) ?? christmasEve,
            calendar.startOfDay(for: Self.nextWeekday(after: boxingDay, calendar: calendar))
        ))

        // New Year's Eve → after Jan 1
        let nyEve       = Self.makeDate(year: year, month: 12, day: 31, calendar: calendar)
        let newYearsDay = Self.makeDate(year: year + 1, month: 1, day: 1, calendar: calendar)
        bRanges.append((
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: nyEve) ?? nyEve,
            calendar.startOfDay(for: Self.nextWeekday(after: newYearsDay, calendar: calendar))
        ))

        tierBRanges = bRanges
    }

    func isTierA(date: Date, calendar: Calendar) -> Bool {
        tierARanges.contains { date >= $0.start && date < $0.end }
    }

    func isTierB(date: Date, calendar: Calendar) -> Bool {
        tierBRanges.contains { date >= $0.start && date < $0.end }
    }

    var allBoundaries: [Date] {
        (tierARanges + tierBRanges).flatMap { [$0.start, $0.end] }
    }

    static func easterSunday(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day   = ((h + l - 7 * m + 114) % 31) + 1
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func ascensionDay(year: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 39, to: easterSunday(year: year)) ?? Date()
    }

    static func allSaintsDay(year: Int, calendar: Calendar) -> Date {
        let base = calendar.date(from: DateComponents(year: year, month: 10, day: 31)) ?? Date()
        for offset in 0..<7 {
            let candidate = calendar.date(byAdding: .day, value: offset, to: base) ?? base
            if calendar.component(.weekday, from: candidate) == 7 { return candidate }
        }
        return base
    }

    static func midsummerEve(year: Int, calendar: Calendar) -> Date {
        for day in 19...25 {
            if let candidate = calendar.date(from: DateComponents(year: year, month: 6, day: day)) {
                if calendar.component(.weekday, from: candidate) == 6 { return candidate }
            }
        }
        return calendar.date(from: DateComponents(year: year, month: 6, day: 19)) ?? Date()
    }

    static func nextWeekday(after date: Date, calendar: Calendar) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        while true {
            let wd = calendar.component(.weekday, from: candidate)
            if wd >= 2 && wd <= 6 { return candidate }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
    }

    static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

class HolidayService: HolidayProviding {
    private var holidayCache: [Int: HolidayDates] = [:]
    
    init() {}
    
    func cachedHolidays(for year: Int, calendar: Calendar) -> HolidayDates {
        if let cached = holidayCache[year] { return cached }
        let h = HolidayDates(year: year, calendar: calendar)
        holidayCache[year] = h
        return h
    }
    
    func invalidateCache() {
        holidayCache.removeAll()
    }
}
