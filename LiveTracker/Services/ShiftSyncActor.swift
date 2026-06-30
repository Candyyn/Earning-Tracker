import SwiftData
import Foundation

struct ShiftSyncRecord: Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let breakStart: Date?
    let breakEnd: Date?
    let breakPaid: Bool
    let calendarEventID: String?
    let syncIdentifier: String
    let dominantShiftType: ShiftType

    init(calendarShift: CalendarShift, dominantShiftType: ShiftType) {
        self.id = calendarShift.id
        self.start = calendarShift.start
        self.end = calendarShift.end
        self.breakStart = calendarShift.breakStart
        self.breakEnd = calendarShift.breakEnd
        self.breakPaid = calendarShift.breakPaid
        self.calendarEventID = calendarShift.calendarEventID
        self.syncIdentifier = calendarShift.syncIdentifier
        self.dominantShiftType = dominantShiftType
    }
}

actor ShiftSyncActor: ModelActor {
    
    let modelContainer: ModelContainer
    let modelExecutor: any ModelExecutor
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }
    
    func syncCalendarShifts(
        _ calendarShifts: [ShiftSyncRecord],
        from start: Date,
        to end: Date
    ) throws {
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.end > start && shift.start < end
            }
        )
        let existingShifts = try modelContext.fetch(descriptor)
        
        var existingByID: [UUID: Shift] = [:]
        var existingBySyncIdentifier: [String: Shift] = [:]
        var existingByEventIdentifier: [String: Shift] = [:]
        for shift in existingShifts {
            existingByID[shift.id] = shift
            if let syncIdentifier = shift.calendarSyncIdentifier {
                existingBySyncIdentifier[syncIdentifier] = shift
            }
            for eventIdentifier in Self.eventIdentifiers(in: shift.calendarEventId) {
                existingByEventIdentifier[eventIdentifier] = shift
            }
        }

        var matchedPersistentIDs = Set<PersistentIdentifier>()

        for fetchedShift in calendarShifts {
            let legacyMatch = Self.eventIdentifiers(in: fetchedShift.calendarEventID)
                .lazy
                .compactMap { existingByEventIdentifier[$0] }
                .first
            if let existing = existingByID[fetchedShift.id]
                ?? existingBySyncIdentifier[fetchedShift.syncIdentifier]
                ?? legacyMatch {
                existing.start = fetchedShift.start
                existing.end = fetchedShift.end
                existing.breakStart = fetchedShift.breakStart
                existing.breakEnd = fetchedShift.breakEnd
                existing.breakPaid = fetchedShift.breakPaid
                existing.calendarEventId = fetchedShift.calendarEventID
                existing.calendarSyncIdentifier = fetchedShift.syncIdentifier
                existing.dominantShiftType = fetchedShift.dominantShiftType
                matchedPersistentIDs.insert(existing.persistentModelID)
            } else {
                let newShift = Shift(
                    id: fetchedShift.id,
                    start: fetchedShift.start,
                    end: fetchedShift.end,
                    breakStart: fetchedShift.breakStart,
                    breakEnd: fetchedShift.breakEnd,
                    breakPaid: fetchedShift.breakPaid,
                    calendarEventId: fetchedShift.calendarEventID,
                    calendarSyncIdentifier: fetchedShift.syncIdentifier
                )
                newShift.dominantShiftType = fetchedShift.dominantShiftType
                modelContext.insert(newShift)
                existingByID[newShift.id] = newShift
                existingBySyncIdentifier[fetchedShift.syncIdentifier] = newShift
                for eventIdentifier in Self.eventIdentifiers(in: fetchedShift.calendarEventID) {
                    existingByEventIdentifier[eventIdentifier] = newShift
                }
            }
        }
        
        for localShift in existingShifts {
            guard localShift.calendarEventId != nil || localShift.calendarSyncIdentifier != nil else { continue }
            if !matchedPersistentIDs.contains(localShift.persistentModelID) {
                modelContext.delete(localShift)
            }
        }
        
        try modelContext.save()
    }

    private static func eventIdentifiers(in value: String?) -> [String] {
        value?.split(separator: ";").map(String.init) ?? []
    }
}
