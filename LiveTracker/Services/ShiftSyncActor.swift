import SwiftData
import Foundation

actor ShiftSyncActor: ModelActor {
    
    let modelContainer: ModelContainer
    let modelExecutor: any ModelExecutor
    
    private let calendarService: CalendarProviding
    private let holidayService: HolidayProviding
    
    init(modelContainer: ModelContainer, calendarService: CalendarProviding, holidayService: HolidayProviding) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.calendarService = calendarService
        self.holidayService = holidayService
    }
    
    func syncCalendarShifts(from start: Date, to end: Date) async throws {
        let calendarShifts = try calendarService.fetchShifts(from: start, to: end)
        
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.start >= start && shift.start <= end
            }
        )
        let existingShifts = (try? modelContext.fetch(descriptor)) ?? []
        
        // 1. Update existing or add new
        for fetchedShift in calendarShifts {
            if let existing = existingShifts.first(where: { $0.id == fetchedShift.id }) {
                existing.start = fetchedShift.start
                existing.end = fetchedShift.end
                existing.breakStart = fetchedShift.breakStart
                existing.breakEnd = fetchedShift.breakEnd
                existing.breakPaid = fetchedShift.breakPaid
                existing.calendarEventId = fetchedShift.calendarEventId
                existing.updateDominantType(holidayService: holidayService)
            } else if let existing = existingShifts.first(where: { $0.calendarEventId == fetchedShift.calendarEventId && fetchedShift.calendarEventId != nil }) {
                existing.start = fetchedShift.start
                existing.end = fetchedShift.end
                existing.breakStart = fetchedShift.breakStart
                existing.breakEnd = fetchedShift.breakEnd
                existing.breakPaid = fetchedShift.breakPaid
                existing.calendarEventId = fetchedShift.calendarEventId
                existing.updateDominantType(holidayService: holidayService)
            } else {
                fetchedShift.updateDominantType(holidayService: holidayService)
                modelContext.insert(fetchedShift)
            }
        }
        
        // 2. Remove shifts that no longer exist in Apple Calendar
        let fetchedIDs = Set(calendarShifts.map { $0.id })
        var fetchedLegacyIDs = Set<String>()
        for fetchedShift in calendarShifts {
            if let legacyId = fetchedShift.calendarEventId {
                let ids = legacyId.split(separator: ";").map(String.init)
                fetchedLegacyIDs.formUnion(ids)
            }
        }
        
        for localShift in existingShifts {
            guard localShift.start >= start && localShift.start <= end else { continue }
            let matchesID = fetchedIDs.contains(localShift.id)
            
            var matchesLegacy = false
            if let localLegacyId = localShift.calendarEventId {
                let localIds = localLegacyId.split(separator: ";").map(String.init)
                if localIds.contains(where: { fetchedLegacyIDs.contains($0) }) {
                    matchesLegacy = true
                }
            }
            
            if !(matchesID || matchesLegacy) {
                modelContext.delete(localShift)
            }
        }
        
        try modelContext.save()
    }
}
