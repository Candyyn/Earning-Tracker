import Foundation
import OSLog

@Observable
@MainActor
final class EarningsTrackerService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LiveTracker",
        category: "EarningsTracker"
    )

    var currentEarnings: Decimal = 0
    var currentlyHourly: Decimal = 0
    var currentShiftType: ShiftType = .day
    var isOnBreak: Bool = false
    
    private let shiftRepository: ShiftRepository
    private let calculator: EarningsCalculating
    private let settingsVM: SettingsViewModel
    private let calendar: Calendar
    private let now: () -> Date
    
    private var completedShiftIDs: Set<UUID> = []
    private var completedShiftsEarnings: Decimal = 0
    private var settingsRevision: UInt64?
    private var updateTask: Task<Void, Never>?
    
    init(
        shiftRepository: ShiftRepository,
        calculator: EarningsCalculating,
        settingsVM: SettingsViewModel,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.shiftRepository = shiftRepository
        self.calculator = calculator
        self.settingsVM = settingsVM
        self.calendar = calendar
        self.now = now
    }
    
    func invalidateCache() {
        let wasRunning = updateTask != nil
        if wasRunning {
            stopTimer()
        }
        resetCache()
        if wasRunning {
            startTimer()
        } else {
            updateEarnings()
        }
    }

    private func resetCache() {
        completedShiftsEarnings = 0
        completedShiftIDs.removeAll()
    }
    
    func startTimer() {
        guard updateTask == nil else { return }
        updateEarnings()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                var sleepInterval: TimeInterval = 60.0
                let now = self.now()
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
                    let nextBoundary = self.calculator.nextRateBoundary(after: now, calendar: self.calendar)
                    let timeToBoundary = nextBoundary.timeIntervalSince(now)
                    sleepInterval = min(sleepInterval, timeToBoundary)
                }
                
                sleepInterval = max(1.0, min(sleepInterval, 60.0))
                do {
                    try await Task.sleep(for: .seconds(sleepInterval))
                } catch {
                    break
                }
                self.updateEarnings()
            }
        }
    }
    
    func stopTimer() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    private func updateEarnings() {
        let now = now()

        do {
            if try shiftRepository.refreshShiftsIfMonthChanged(
                referenceDate: now,
                calendar: calendar
            ) {
                resetCache()
            }
        } catch {
            Self.logger.error("Could not refresh shifts after the month changed: \(error.localizedDescription)")
        }

        if settingsRevision != settingsVM.revision {
            resetCache()
            settingsRevision = settingsVM.revision
        }

        var activeTotal: Decimal = 0

        let paySettingsProvider: (Date) -> PaySettings? = { [weak self] date in
            self?.settingsVM.paySettings(for: date)
        }
        
        // Update break state
        self.isOnBreak = shiftRepository.currentMonthShifts.contains { shift in
            guard now >= shift.start, now < shift.end else { return false }
            guard let bStart = shift.breakStart, let bEnd = shift.breakEnd else { return false }
            return now >= bStart && now < bEnd
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
            }
        }

        let total = completedShiftsEarnings + activeTotal
        currentEarnings = total
        
        let rate = calculator.hourlyRate(for: now, calendar: calendar, paySettingsProvider: paySettingsProvider)
        currentlyHourly = rate
        let type = calculator.currentType(for: now, calendar: calendar)
        currentShiftType = type
    }
}
