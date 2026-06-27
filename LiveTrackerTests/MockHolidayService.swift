import Foundation
@testable import LiveTracker

class MockHolidayService: HolidayProviding {
    
    func cachedHolidays(for year: Int, calendar: Calendar) -> HolidayDates {
        // Return a deterministic set of holidays for testing.
        // We will define May 1st as Tier A and Dec 24th as Tier B.
        
        let tierADates = [
            calendar.date(from: DateComponents(year: year, month: 5, day: 1))!
        ]
        
        let tierBDates = [
            calendar.date(from: DateComponents(year: year, month: 12, day: 24))!
        ]
        let tierARanges = tierADates.map {
            (start: $0, end: calendar.date(byAdding: .day, value: 1, to: $0)!)
        }
        
        let tierBRanges = tierBDates.map {
            (start: $0, end: calendar.date(byAdding: .day, value: 1, to: $0)!)
        }
        
        return HolidayDates(tierARanges: tierARanges, tierBRanges: tierBRanges)
    }
    
    func invalidateCache() {
        // No-op for mock
    }
}
