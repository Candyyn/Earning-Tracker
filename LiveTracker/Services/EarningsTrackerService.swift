import Foundation

@Observable
@MainActor
class EarningsTrackerService {
    var currentEarnings: Double = 0.0
    var currentlyHourly: Double = 0.0
    var currentShiftType: ShiftType = .day
    var isOnBreak: Bool = false
    
    private let shiftRepository: ShiftRepository
    private let calculator: EarningsCalculating
    private let settingsVM: SettingsViewModel
    
    private var completedShiftIDs: Set<UUID> = []
    private var completedShiftsEarnings: Double = 0
    private var updateTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    
    init(shiftRepository: ShiftRepository, calculator: EarningsCalculating, settingsVM: SettingsViewModel) {
        self.shiftRepository = shiftRepository
        self.calculator = calculator
        self.settingsVM = settingsVM
    }
    
    func invalidateCache() {
        completedShiftsEarnings = 0
        completedShiftIDs.removeAll()
    }
    
    func startTimer() {
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                self.updateEarnings()
                
                var sleepInterval: TimeInterval = 60.0
                let now = Date()
                let hasActiveShift = self.shiftRepository.currentMonthShifts.contains { shift in
                    now >= shift.start && now < shift.end
                }
                
                if hasActiveShift {
                    sleepInterval = 1.0
                } else {
                    for shift in self.shiftRepository.currentMonthShifts {
                        if shift.start > now {
                            let timeToStart = shift.start.timeIntervalSince(now)
                            sleepInterval = min(sleepInterval, timeToStart)
                        }
                    }
                    let nextBoundary = self.calculator.nextRateBoundary(after: now, calendar: .current)
                    let timeToBoundary = nextBoundary.timeIntervalSince(now)
                    sleepInterval = min(sleepInterval, timeToBoundary)
                }
                
                sleepInterval = max(1.0, min(sleepInterval, 60.0))
                try? await Task.sleep(for: .seconds(sleepInterval))
            }
        }
    }
    
    func stopTimer() {
        updateTask?.cancel()
        updateTask = nil
        debounceTask?.cancel()
    }
    
    private func updateEarnings() {
        let now = Date()
        let calendar = Calendar.current

        var activeTotal: Double = 0
        var activeShift: Shift? = nil

        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        
        // Update break state
        self.isOnBreak = shiftRepository.currentMonthShifts.contains { shift in
            guard now >= shift.start, now <= shift.end else { return false }
            guard let bStart = shift.breakStart, let bEnd = shift.breakEnd else { return false }
            return now >= bStart && now <= bEnd
        }

        for shift in shiftRepository.currentMonthShifts {
            guard now >= shift.start else { continue }

            if now >= shift.end {
                if !completedShiftIDs.contains(shift.id) {
                    completedShiftsEarnings += calculator.earningsForFullShift(shift, calendar: calendar, paySettingsProvider: paySettingsProvider)
                    completedShiftIDs.insert(shift.id)
                }
            } else {
                activeTotal += calculator.earningsForActiveShift(shift, now: now, calendar: calendar, paySettingsProvider: paySettingsProvider)
                activeShift = shift
            }
        }

        let total = completedShiftsEarnings + activeTotal
        currentEarnings = total
        
        let rate = calculator.hourlyRate(for: now, calendar: calendar, paySettingsProvider: paySettingsProvider)
        currentlyHourly = rate
        let type = calculator.currentType(for: now)
        currentShiftType = type
        LiveActivityManager.shared.manageLiveActivity(for: activeShift, activeTotal: activeTotal, currentRate: rate, shiftType: type)
        
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self = self else { return }
            let defaults = UserDefaults(suiteName: "group.studio.magnusson.livetracker")
            defaults?.set(self.currentEarnings, forKey: "currentEarnings")
        }
    }
}
