import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class EarningsViewModel {
    let settingsVM: SettingsViewModel
    let shiftRepository: ShiftRepository
    let trackerService: EarningsTrackerService
    let calculator: EarningsCalculating
    let calendarSync: CalendarSyncCoordinator
    
    var currentEarnings: Decimal { trackerService.currentEarnings }
    var currentlyHourly: Decimal { trackerService.currentlyHourly }
    var currentShiftType: ShiftType { trackerService.currentShiftType }
    var currentMonthShifts: [Shift] { shiftRepository.currentMonthShifts }
    var errorMessage: String?

    private var hasStarted = false
    private let legacyDefaults: UserDefaults
    
    init(
        settingsVM: SettingsViewModel,
        shiftRepository: ShiftRepository,
        trackerService: EarningsTrackerService,
        calculator: EarningsCalculating,
        calendarSync: CalendarSyncCoordinator,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.settingsVM = settingsVM
        self.shiftRepository = shiftRepository
        self.trackerService = trackerService
        self.calculator = calculator
        self.calendarSync = calendarSync
        self.legacyDefaults = legacyDefaults
    }
    
    var modelContext: ModelContext {
        shiftRepository.modelContext
    }
    
    // MARK: - Initial Migration (Legacy)
    
    func start() {
        if !hasStarted {
            hasStarted = true
            do {
                try migrateUserDefaultsToSwiftDataIfNeeded()
                try refreshShifts()
            } catch {
                errorMessage = "Dina sparade pass kunde inte läsas: \(error.localizedDescription)"
            }
        }
        trackerService.startTimer()
    }

    func stop() {
        trackerService.stopTimer()
    }

    private func migrateUserDefaultsToSwiftDataIfNeeded() throws {
        guard let data = legacyDefaults.data(forKey: "Shifts") else { return }

        let decoded = try JSONDecoder().decode([LegacyShift].self, from: data)
        let descriptor = FetchDescriptor<Shift>()
        let existingCount = try modelContext.fetchCount(descriptor)

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
            try modelContext.save()
        }
        legacyDefaults.removeObject(forKey: "Shifts")
    }
    
    // MARK: - Shift Management
    
    func refreshShifts() throws {
        try shiftRepository.refreshShifts()
        trackerService.invalidateCache()
    }
    
    func importCalendarShifts() async throws {
        try await shiftRepository.importCalendarShifts()
        trackerService.invalidateCache()
    }

    func connectCalendar() async throws {
        try await calendarSync.connect()
        try await synchronizeCalendarIfEnabled()
    }

    func synchronizeCalendarIfEnabled() async throws {
        try await calendarSync.performSync { [self] in
            try shiftRepository.exportUnsyncedCalendarShifts()
            try await importCalendarShifts()
        }
    }

    func shifts(from start: Date, to end: Date) throws -> [Shift] {
        try shiftRepository.shifts(from: start, to: end)
    }
    
    func isOnBreak() -> Bool {
        trackerService.isOnBreak
    }
    
    // MARK: - Proxies for UI
    
    func hourlyRate(for date: Date) -> Decimal {
        calculator.hourlyRate(for: date, calendar: .current) { [weak self] d in
            self?.settingsVM.paySettings(for: d)
        }
    }
    
    func currentType(for date: Date) -> ShiftType {
        calculator.currentType(for: date, calendar: .current)
    }
    
    func earningsForFullShift(_ shift: Shift) -> Decimal {
        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        return calculator.earningsForFullShift(shift, calendar: .current, paySettingsProvider: paySettingsProvider)
    }
    
    // MARK: - Shift Month Stats
    
    func totalEarningsForShifts(_ shifts: [Shift]) -> Decimal {
        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        
        return shifts.reduce(0) { total, shift in
            let segments = calculator.workSegments(for: shift, workedUntil: shift.end)
            return total + segments.reduce(0) {
                $0 + calculator.earningsForShift(from: $1.start, to: $1.end, calendar: .current, paySettingsProvider: paySettingsProvider)
            }
        }
    }

    func workedHoursByType(for shifts: [Shift]) -> HoursByShiftType {
        var hoursByType = HoursByShiftType()
        
        for shift in shifts {
            for segment in calculator.workSegments(for: shift, workedUntil: shift.end) {
                var current = segment.start
                while current < segment.end {
                    let boundary = calculator.nextRateBoundary(after: current, calendar: Calendar.current)
                    let segEnd = min(boundary, segment.end)
                    let type = calculator.currentType(for: current, calendar: .current)
                    let seconds = segEnd.timeIntervalSince(current)
                    hoursByType.add(hours: seconds / 3600.0, for: type)
                    current = segEnd
                }
            }
        }
        return hoursByType
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
