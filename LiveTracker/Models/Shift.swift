//
//  Shift.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import SwiftData

@Model
final class Shift: Identifiable, Equatable {
    var id: UUID
    var start: Date
    var end: Date
    var breakStart: Date?
    var breakEnd: Date?
    var breakPaid: Bool
    
    var calendarEventId: String?
    var dominantShiftType: ShiftType?
    
    init(id: UUID = UUID(), start: Date, end: Date, breakStart: Date? = nil, breakEnd: Date? = nil, breakPaid: Bool = false, calendarEventId: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.breakStart = breakStart
        self.breakEnd = breakEnd
        self.breakPaid = breakPaid
        self.calendarEventId = calendarEventId
        self.dominantShiftType = nil
    }
    
    func updateDominantType(holidayService: HolidayProviding) {
        self.dominantShiftType = calculateDominantType(holidayService: holidayService)
    }
    
    private func calculateDominantType(holidayService: HolidayProviding) -> ShiftType {
        let calendar = Calendar.current
        let step: TimeInterval = 15 * 60
        var counts: [ShiftType: TimeInterval] = [
            .day: 0, .evening: 0, .night: 0, .weekend: 0, .holiday: 0, .holidayMajor: 0
        ]

        var current = start
        while current < end {
            let next = current.addingTimeInterval(step)
            let sliceEnd = min(next, end)
            let duration = sliceEnd.timeIntervalSince(current)

            let type = currentType(for: current, calendar: calendar, holidayService: holidayService)
            counts[type, default: 0] += duration

            current = next
        }

        if counts[.holidayMajor, default: 0] > 0 { return .holidayMajor }
        if counts[.holiday, default: 0] > 0 { return .holiday }

        let weekendOnly = counts[.weekend, default: 0] > 0
            && counts[.day, default: 0] + counts[.evening, default: 0] + counts[.night, default: 0] == 0
        if weekendOnly { return .weekend }

        return counts.max(by: { $0.value < $1.value })?.key ?? .day
    }
    
    private func currentType(for date: Date, calendar: Calendar, holidayService: HolidayProviding) -> ShiftType {
        let hour    = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let year    = calendar.component(.year, from: date)

        let holidays = holidayService.cachedHolidays(for: year, calendar: calendar)
        
        if holidays.isTierB(date: date, calendar: calendar) {
            return .holidayMajor
        }
        if holidays.isTierA(date: date, calendar: calendar) {
            return .holiday
        }

        if weekday == 1 || weekday == 7 { return .weekend }

        switch hour {
        case 8..<18:  return .day
        case 18..<24: return .evening
        default:      return .night
        }
    }
}
