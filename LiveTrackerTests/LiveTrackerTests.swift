//
//  LiveTrackerTests.swift
//  LiveTrackerTests
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Testing
import Foundation
@testable import LiveTracker

@MainActor
struct LiveTrackerTests {
    
    let mockHolidayService = MockHolidayService()
    let calculator: EarningsCalculator
    
    init() {
        self.calculator = EarningsCalculator(holidayService: mockHolidayService)
    }
    
    private func createTestSettings(hourlyRate: Double) -> PaySettings {
        var settings = PaySettings(hourlyRate: hourlyRate, startRange: Date.distantPast, endRange: Date.distantFuture)
        settings.recalculateRates()
        return settings
    }
    
    private func createDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: comps)!
    }
    
    @Test func testWeekdayDayShift() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        let start = createDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0) // Monday
        let end = createDate(year: 2026, month: 6, day: 15, hour: 17, minute: 0)
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        #expect(earnings == 8 * settings.dayRate)
    }
    
    @Test func testShiftWithUnpaidBreak() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        let start = createDate(year: 2026, month: 6, day: 15, hour: 8, minute: 0) // Monday
        let end = createDate(year: 2026, month: 6, day: 15, hour: 17, minute: 0)
        let breakStart = createDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
        let breakEnd = createDate(year: 2026, month: 6, day: 15, hour: 13, minute: 0)
        
        let shift = Shift(start: start, end: end, breakStart: breakStart, breakEnd: breakEnd, breakPaid: false)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        // Should be 8 hours worked (9 total minus 1 unpaid break)
        #expect(earnings == 8 * settings.dayRate)
    }
    
    @Test func testShiftCrossingMidnight() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        let start = createDate(year: 2026, month: 6, day: 15, hour: 22, minute: 0) // Monday
        let end = createDate(year: 2026, month: 6, day: 16, hour: 2, minute: 0) // Tuesday
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        // 22:00 - 24:00 is 2 hours of evening rate
        // 00:00 - 02:00 is 2 hours of night rate
        let expectedEarnings = (2 * settings.eveningRate) + (2 * settings.nightRate)
        #expect(earnings == expectedEarnings)
    }

    @Test func testHolidayRateCanStartInsideNightBand() throws {
        let settings = createTestSettings(hourlyRate: 150)
        let calculator = EarningsCalculator(holidayService: HolidayService())
        
        // Jan 6 is a Tier A holiday. The configured holiday range starts at 07:00,
        // so this must split into one night hour and one holiday hour.
        let start = createDate(year: 2026, month: 1, day: 6, hour: 6, minute: 0)
        let end = createDate(year: 2026, month: 1, day: 6, hour: 8, minute: 0)
        let shift = Shift(start: start, end: end)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        #expect(earnings == settings.nightRate + settings.holidayRateA)
    }
    
    @Test func testWeekendShift() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        let start = createDate(year: 2026, month: 6, day: 13, hour: 8, minute: 0) // Saturday
        let end = createDate(year: 2026, month: 6, day: 13, hour: 12, minute: 0)
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        #expect(earnings == 4 * settings.weekendRate)
    }
    
    @Test func testHolidayShiftTierA() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        // May 1st is Tier A holiday as per mock
        let start = createDate(year: 2026, month: 5, day: 1, hour: 10, minute: 0)
        let end = createDate(year: 2026, month: 5, day: 1, hour: 14, minute: 0)
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        #expect(earnings == 4 * settings.holidayRateA)
    }
    
    @Test func testMajorHolidayShiftTierB() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        // Christmas Eve (Dec 24th) is Tier B major holiday as per mock
        let start = createDate(year: 2026, month: 12, day: 24, hour: 10, minute: 0)
        let end = createDate(year: 2026, month: 12, day: 24, hour: 14, minute: 0)
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        #expect(earnings == 4 * settings.holidayRateB)
    }
    
    @Test func testActiveShiftEarnings() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        let start = createDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0)
        let end = createDate(year: 2026, month: 6, day: 15, hour: 17, minute: 0)
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        // Active time is 11:30 AM (2.5 hours into shift)
        let now = createDate(year: 2026, month: 6, day: 15, hour: 11, minute: 30)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let activeEarnings = calculator.earningsForActiveShift(shift, now: now, calendar: .current, paySettingsProvider: provider)
        
        #expect(activeEarnings == 2.5 * settings.dayRate)
    }

    @Test func testWorkSegmentsExcludeUnpaidBreak() throws {
        let start = createDate(year: 2026, month: 6, day: 15, hour: 8, minute: 0)
        let end = createDate(year: 2026, month: 6, day: 15, hour: 17, minute: 0)
        let breakStart = createDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
        let breakEnd = createDate(year: 2026, month: 6, day: 15, hour: 13, minute: 0)
        let shift = Shift(start: start, end: end, breakStart: breakStart, breakEnd: breakEnd, breakPaid: false)
        
        let segments = calculator.workSegments(for: shift, workedUntil: shift.end)
        
        #expect(segments.count == 2)
        #expect(segments[0].0 == start)
        #expect(segments[0].1 == breakStart)
        #expect(segments[1].0 == breakEnd)
        #expect(segments[1].1 == end)
    }
    
    @Test func testComplexRateBoundary() throws {
        let settings = createTestSettings(hourlyRate: 150)
        
        // Friday 16:00 to Saturday 02:00
        let start = createDate(year: 2026, month: 6, day: 12, hour: 16, minute: 0) // Friday
        let end = createDate(year: 2026, month: 6, day: 13, hour: 2, minute: 0) // Saturday
        let shift = Shift(start: start, end: end)
        shift.updateDominantType(holidayService: mockHolidayService)
        
        let provider: (Date) -> PaySettings? = { _ in settings }
        let earnings = calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: provider)
        
        // 16:00 - 18:00 (2 hours) = Day Rate
        // 18:00 - 24:00 (6 hours) = Evening Rate
        // 00:00 - 02:00 (2 hours) = Weekend Rate (Saturday)
        
        let expectedEarnings = (2 * settings.dayRate) + (6 * settings.eveningRate) + (2 * settings.weekendRate)
        #expect(earnings == expectedEarnings)
    }
}
