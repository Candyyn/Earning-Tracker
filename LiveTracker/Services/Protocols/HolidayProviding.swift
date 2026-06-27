import Foundation

protocol HolidayProviding {
    func cachedHolidays(for year: Int, calendar: Calendar) -> HolidayDates
    func invalidateCache()
}
