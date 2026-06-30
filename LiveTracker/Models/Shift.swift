//
//  Shift.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import SwiftData

@Model
final class Shift: Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var breakStart: Date?
    var breakEnd: Date?
    var breakPaid: Bool
    
    var calendarEventId: String?
    var calendarSyncIdentifier: String?
    var dominantShiftType: ShiftType?
    
    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        breakStart: Date? = nil,
        breakEnd: Date? = nil,
        breakPaid: Bool = false,
        calendarEventId: String? = nil,
        calendarSyncIdentifier: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.breakStart = breakStart
        self.breakEnd = breakEnd
        self.breakPaid = breakPaid
        self.calendarEventId = calendarEventId
        self.calendarSyncIdentifier = calendarSyncIdentifier
        self.dominantShiftType = nil
    }
    
    @MainActor
    func updateDominantType(holidayService: HolidayProviding) {
        dominantShiftType = Self.calculateDominantType(
            start: start,
            end: end,
            holidayService: holidayService
        )
    }

    @MainActor
    static func calculateDominantType(
        start: Date,
        end: Date,
        holidayService: HolidayProviding
    ) -> ShiftType {
        guard start < end else { return .day }

        let calendar = Calendar.current
        let step: TimeInterval = 15 * 60
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let holidays = ((startYear - 1)...(endYear + 1)).map {
            holidayService.cachedHolidays(for: $0, calendar: calendar)
        }
        var counts: [ShiftType: TimeInterval] = [
            .day: 0, .evening: 0, .night: 0, .weekend: 0, .holiday: 0, .holidayMajor: 0
        ]

        var current = start
        while current < end {
            let next = current.addingTimeInterval(step)
            let sliceEnd = min(next, end)
            let duration = sliceEnd.timeIntervalSince(current)

            let type = RateSchedule.standard.shiftType(
                for: current,
                calendar: calendar,
                holidays: holidays
            )
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
}
