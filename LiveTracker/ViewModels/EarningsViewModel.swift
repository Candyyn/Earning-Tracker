import SwiftUI
import SwiftData
import Combine

@Observable
@MainActor
class EarningsViewModel {
    let settingsVM: SettingsViewModel
    let shiftRepository: ShiftRepository
    let trackerService: EarningsTrackerService
    let calculator: EarningsCalculating
    
    var currentEarnings: Double { trackerService.currentEarnings }
    var currentlyHourly: Double { trackerService.currentlyHourly }
    var currentShiftType: ShiftType { trackerService.currentShiftType }
    var currentMonthShifts: [Shift] { shiftRepository.currentMonthShifts }
    
    init(settingsVM: SettingsViewModel, shiftRepository: ShiftRepository, trackerService: EarningsTrackerService, calculator: EarningsCalculating) {
        self.settingsVM = settingsVM
        self.shiftRepository = shiftRepository
        self.trackerService = trackerService
        self.calculator = calculator
        
        shiftRepository.refreshShifts()
        trackerService.startTimer()
        shiftRepository.importCalendarShifts()
        
        migrateUserDefaultsToSwiftDataIfNeeded()
    }
    
    var modelContext: ModelContext {
        shiftRepository.modelContext
    }
    
    // MARK: - Initial Migration (Legacy)
    
    private func migrateUserDefaultsToSwiftDataIfNeeded() {
        if let data = UserDefaults.standard.data(forKey: "Shifts"),
           let decoded = try? JSONDecoder().decode([LegacyShift].self, from: data) {
            
            let descriptor = FetchDescriptor<Shift>()
            let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            
            if existingCount == 0 {
                for legacyShift in decoded {
                    let newShift = Shift(
                        id: legacyShift.id,
                        start: legacyShift.start,
                        end: legacyShift.end,
                        breakStart: legacyShift.breakStart,
                        breakEnd: legacyShift.breakEnd,
                        breakPaid: legacyShift.breakPaid,
                        calendarEventId: legacyShift.calendarEventId
                    )
                    modelContext.insert(newShift)
                }
                do {
                    try modelContext.save()
                    UserDefaults.standard.removeObject(forKey: "Shifts")
                } catch {
                    print("Failed to save migrated shifts: \(error)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "Shifts")
            }
        }
    }
    
    // MARK: - Shift Management
    
    func refreshShifts() {
        shiftRepository.refreshShifts()
        trackerService.invalidateCache()
    }
    
    func importCalendarShifts() {
        shiftRepository.importCalendarShifts()
    }
    
    func isOnBreak() -> Bool {
        trackerService.isOnBreak
    }
    
    // MARK: - Proxies for UI
    
    func hourlyRate(for date: Date) -> Double {
        calculator.hourlyRate(for: date, calendar: .current) { [weak self] d in
            self?.settingsVM.paySettings(for: d)
        }
    }
    
    func currentType(for date: Date) -> ShiftType {
        calculator.currentType(for: date)
    }
    
    func earningsForFullShift(_ shift: Shift) -> Double {
        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        return calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: paySettingsProvider)
    }
    
    // MARK: - Shift Month Stats
    
    func totalEarningsForShifts(_ shifts: [Shift]) -> Double {
        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        
        return shifts.reduce(0) { total, shift in
            let segments = calculator.workSegments(for: shift, workedUntil: shift.end)
            return total + segments.reduce(0) {
                $0 + calculator.earningsForShift(from: $1.0, to: $1.1, calendar: .current, paySettingsProvider: paySettingsProvider)
            }
        }
    }

    func workedHoursByType(for shifts: [Shift]) -> (day: Double, evening: Double, night: Double, weekend: Double, holiday: Double, holidayMajor: Double, total: Double) {
        var day: Double = 0, evening: Double = 0, night: Double = 0, weekend: Double = 0, holiday: Double = 0, holidayMajor: Double = 0
        
        for shift in shifts {
            for (segmentStart, segmentEnd) in calculator.workSegments(for: shift, workedUntil: shift.end) {
                var current = segmentStart
                while current < segmentEnd {
                    let boundary = calculator.nextRateBoundary(after: current, calendar: Calendar.current)
                    let segEnd = min(boundary, segmentEnd)
                    let type = calculator.currentType(for: current)
                    let seconds = segEnd.timeIntervalSince(current)
                    let hours = seconds / 3600.0
                    switch type {
                    case .day: day += hours
                    case .evening: evening += hours
                    case .night: night += hours
                    case .weekend: weekend += hours
                    case .holiday: holiday += hours
                    case .holidayMajor: holidayMajor += hours
                    }
                    current = segEnd
                }
            }
        }
        let total = day + evening + night + weekend + holiday + holidayMajor
        return (day, evening, night, weekend, holiday, holidayMajor, total)
    }
}

// MARK: - Legacy Migration

struct LegacyShift: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var breakStart: Date?
    var breakEnd: Date?
    var breakPaid: Bool
    var calendarEventId: String?
}
