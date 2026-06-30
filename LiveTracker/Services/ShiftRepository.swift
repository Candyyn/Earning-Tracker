import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ShiftRepository {
    private(set) var currentMonthShifts: [Shift] = []
    private(set) var currentMonthStart: Date?
    
    let modelContext: ModelContext
    let holidayService: HolidayProviding
    let calendarService: CalendarProviding
    
    init(modelContext: ModelContext, holidayService: HolidayProviding, calendarService: CalendarProviding) {
        self.modelContext = modelContext
        self.holidayService = holidayService
        self.calendarService = calendarService
    }
    
    func refreshShifts(referenceDate: Date = .now, calendar: Calendar = .current) throws {
        guard let start = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ), let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            throw CocoaError(.coderInvalidValue)
        }
        
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.start >= start && shift.start < end
            }
        )

        currentMonthShifts = try modelContext.fetch(descriptor)
        currentMonthStart = start
        var updatedDominantType = false
        for shift in currentMonthShifts where shift.dominantShiftType == nil {
            shift.updateDominantType(holidayService: holidayService)
            updatedDominantType = true
        }
        if updatedDominantType {
            try modelContext.save()
        }
    }

    @discardableResult
    func refreshShiftsIfMonthChanged(
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Bool {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        guard currentMonthStart != monthStart else { return false }

        try refreshShifts(referenceDate: referenceDate, calendar: calendar)
        return true
    }
    
    func delete(_ shift: Shift) throws {
        try delete([shift])
    }

    func delete(_ shifts: [Shift]) throws {
        for shift in shifts {
            modelContext.delete(shift)
        }
        try modelContext.save()
        try refreshShifts()
    }
    
    func insert(_ shift: Shift) throws {
        modelContext.insert(shift)
        try modelContext.save()
        try refreshShifts()
    }
    
    func save() throws {
        try modelContext.save()
        try refreshShifts()
    }

    func shifts(from start: Date, to end: Date) throws -> [Shift] {
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.end > start && shift.start < end
            },
            sortBy: [SortDescriptor(\Shift.start)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func importCalendarShifts(referenceDate: Date = .now, calendar: Calendar = .current) async throws {
        let interval = try calendarSyncInterval(referenceDate: referenceDate, calendar: calendar)
        let calendarShifts = try calendarService.fetchShifts(
            from: interval.start,
            to: interval.end
        )
        let syncRecords = calendarShifts.map { shift in
            ShiftSyncRecord(
                calendarShift: shift,
                dominantShiftType: Shift.calculateDominantType(
                    start: shift.start,
                    end: shift.end,
                    holidayService: holidayService
                )
            )
        }

        let container = modelContext.container
        let syncActor = ShiftSyncActor(modelContainer: container)
        try await syncActor.syncCalendarShifts(
            syncRecords,
            from: interval.start,
            to: interval.end
        )
        try refreshShifts(referenceDate: referenceDate, calendar: calendar)
    }

    func exportUnsyncedCalendarShifts(
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let interval = try calendarSyncInterval(referenceDate: referenceDate, calendar: calendar)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.end > start && shift.start < end && shift.calendarEventId == nil
            },
            sortBy: [SortDescriptor(\Shift.start)]
        )

        for shift in try modelContext.fetch(descriptor) {
            let link = try calendarService.save(shift)
            shift.calendarEventId = link.eventIdentifiers
            shift.calendarSyncIdentifier = link.syncIdentifier
            try modelContext.save()
        }
    }

    private func calendarSyncInterval(
        referenceDate: Date,
        calendar: Calendar
    ) throws -> DateInterval {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ),
              let start = calendar.date(byAdding: .month, value: -1, to: monthStart),
              let end = calendar.date(byAdding: .month, value: 2, to: monthStart) else {
            throw CocoaError(.coderInvalidValue)
        }
        return DateInterval(start: start, end: end)
    }
}
