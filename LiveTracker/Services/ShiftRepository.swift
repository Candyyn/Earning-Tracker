import Foundation
import SwiftData

@Observable
@MainActor
class ShiftRepository {
    var currentMonthShifts: [Shift] = []
    
    let modelContext: ModelContext
    let holidayService: HolidayProviding
    let calendarService: CalendarProviding
    
    init(modelContext: ModelContext, holidayService: HolidayProviding, calendarService: CalendarProviding) {
        self.modelContext = modelContext
        self.holidayService = holidayService
        self.calendarService = calendarService
    }
    
    func refreshShifts() {
        let now = Date()
        let calendar = Calendar.current
        
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else { return }
        
        let start = startOfMonth
        guard let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfMonth) else { return }
        
        let descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { shift in
                shift.start >= start && shift.start <= end
            }
        )
        
        if let monthShifts = try? modelContext.fetch(descriptor) {
            currentMonthShifts = monthShifts
            for shift in currentMonthShifts {
                if shift.dominantShiftType == nil {
                    shift.updateDominantType(holidayService: holidayService)
                }
            }
        }
    }
    
    func delete(_ shift: Shift) {
        modelContext.delete(shift)
        try? modelContext.save()
        refreshShifts()
    }
    
    func insert(_ shift: Shift) {
        modelContext.insert(shift)
        try? modelContext.save()
        refreshShifts()
    }
    
    func save() {
        try? modelContext.save()
        refreshShifts()
    }
    
    func importCalendarShifts() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()

        let container = modelContext.container
        Task {
            let syncActor = ShiftSyncActor(modelContainer: container, calendarService: calendarService, holidayService: holidayService)
            do {
                try await syncActor.syncCalendarShifts(from: start, to: end)
                
                await MainActor.run { [weak self] in
                    self?.refreshShifts()
                }
            } catch {
                print("Calendar import failed:", error)
            }
        }
    }
}
