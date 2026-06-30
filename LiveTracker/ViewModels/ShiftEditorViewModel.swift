import Foundation
import Observation

@Observable
@MainActor
final class ShiftEditorViewModel {
    var start: Date
    var end: Date
    var breakStart: Date
    var breakEnd: Date
    var breakPaid = false
    var includeBreak = false
    var editingShiftID: UUID?
    var selectedMonth: Date
    var errorMessage: String?
    var isEditorPresented = false
    var isDiscardConfirmationPresented = false

    private struct Snapshot: Equatable {
        let start: Date
        let end: Date
        let breakStart: Date
        let breakEnd: Date
        let breakPaid: Bool
        let includeBreak: Bool
    }

    private let earningsViewModel: EarningsViewModel
    private let calendar: Calendar
    private let now: () -> Date
    private var originalSnapshot: Snapshot?

    init(
        earningsViewModel: EarningsViewModel,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        let currentDate = now()
        self.earningsViewModel = earningsViewModel
        self.calendar = calendar
        self.now = now
        self.start = currentDate
        self.end = currentDate
        self.breakStart = currentDate
        self.breakEnd = currentDate
        self.selectedMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: currentDate)
        ) ?? currentDate
    }

    var isEditing: Bool {
        editingShiftID != nil
    }

    var isValid: Bool {
        validationMessage == nil
    }

    var validationMessage: String? {
        guard start < end else { return "Passet måste sluta efter att det börjar." }
        guard end.timeIntervalSince(start) <= 24 * 60 * 60 else {
            return "Ett pass kan inte vara längre än 24 timmar."
        }
        if includeBreak && !(start <= breakStart && breakStart < breakEnd && breakEnd <= end) {
            return "Rasten måste ligga inom passet och sluta efter att den börjar."
        }
        return nil
    }

    var isDirty: Bool {
        guard let originalSnapshot else { return false }
        return snapshot != originalSnapshot
    }

    func synchronizeCalendarIfEnabled() async {
        earningsViewModel.calendarSync.refreshAuthorizationState()
        guard earningsViewModel.calendarSync.shouldSynchronize else { return }
        do {
            try await earningsViewModel.synchronizeCalendarIfEnabled()
        } catch {
            errorMessage = "Kalendersynken misslyckades: \(error.localizedDescription)"
        }
    }

    func connectCalendar() async {
        do {
            try await earningsViewModel.connectCalendar()
        } catch {
            errorMessage = "Kalendern kunde inte anslutas: \(error.localizedDescription)"
        }
    }

    func presentNewShift(referenceDate: Date? = nil) {
        let currentDate = now()
        let targetDate = referenceDate ?? currentDate
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: currentDate)
        var components = dateComponents
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        let proposedStart = calendar.date(from: components) ?? targetDate

        start = proposedStart
        end = proposedStart.addingTimeInterval(8 * 60 * 60)
        breakStart = proposedStart.addingTimeInterval(4 * 60 * 60)
        breakEnd = proposedStart.addingTimeInterval(5 * 60 * 60)
        includeBreak = false
        breakPaid = false
        editingShiftID = nil
        errorMessage = nil
        originalSnapshot = snapshot
        isEditorPresented = true
    }

    func save(allShifts: [Shift]) {
        guard isValid else {
            errorMessage = validationMessage
            return
        }

        let repository = earningsViewModel.shiftRepository
        let shift: Shift
        let isNewShift: Bool

        if let editingShiftID,
           let existing = allShifts.first(where: { $0.id == editingShiftID }) {
            shift = existing
            isNewShift = false
        } else {
            shift = Shift(start: start, end: end)
            isNewShift = true
        }

        shift.start = start
        shift.end = end
        shift.breakStart = includeBreak ? breakStart : nil
        shift.breakEnd = includeBreak ? breakEnd : nil
        shift.breakPaid = includeBreak && breakPaid
        shift.updateDominantType(holidayService: repository.holidayService)

        do {
            if isNewShift {
                try repository.insert(shift)
            } else {
                try repository.save()
            }
            earningsViewModel.trackerService.invalidateCache()
        } catch {
            errorMessage = "Passet kunde inte sparas: \(error.localizedDescription)"
            return
        }

        if earningsViewModel.calendarSync.shouldSynchronize {
            earningsViewModel.calendarSync.recordSyncStarted()
            let previousCalendarEventID = shift.calendarEventId
            let previousCalendarSyncIdentifier = shift.calendarSyncIdentifier
            do {
                let link = try repository.calendarService.save(shift)
                shift.calendarEventId = link.eventIdentifiers
                shift.calendarSyncIdentifier = link.syncIdentifier
                try repository.save()
                earningsViewModel.calendarSync.recordSyncSucceeded()
            } catch {
                earningsViewModel.calendarSync.recordSyncFailure(error)
                shift.calendarEventId = previousCalendarEventID
                shift.calendarSyncIdentifier = previousCalendarSyncIdentifier
                do {
                    try repository.save()
                    errorMessage = "Passet sparades lokalt, men kalendersynken misslyckades: \(error.localizedDescription)"
                } catch let persistenceError {
                    errorMessage = "Kalendersynken misslyckades och försöksläget kunde inte sparas: \(persistenceError.localizedDescription)"
                }
            }
        }
        closeEditor()
    }

    func edit(_ shift: Shift) {
        start = shift.start
        end = shift.end
        if let shiftBreakStart = shift.breakStart, let shiftBreakEnd = shift.breakEnd {
            includeBreak = true
            breakStart = shiftBreakStart
            breakEnd = shiftBreakEnd
            breakPaid = shift.breakPaid
        } else {
            includeBreak = false
            let midpoint = shift.start.addingTimeInterval(shift.end.timeIntervalSince(shift.start) / 2)
            breakStart = midpoint
            breakEnd = min(midpoint.addingTimeInterval(60 * 60), shift.end)
            breakPaid = false
        }
        editingShiftID = shift.id
        errorMessage = nil
        originalSnapshot = snapshot
        isEditorPresented = true
    }

    func delete(_ shifts: [Shift]) {
        let repository = earningsViewModel.shiftRepository
        var calendarErrors: [String] = []

        if earningsViewModel.calendarSync.shouldSynchronize {
            earningsViewModel.calendarSync.recordSyncStarted()
            for shift in shifts {
                do {
                    try repository.calendarService.delete(shift)
                } catch {
                    calendarErrors.append(error.localizedDescription)
                }
            }
        }

        if !calendarErrors.isEmpty {
            earningsViewModel.calendarSync.recordSyncFailure(CalendarSyncMutationError.deleteFailed)
            errorMessage = "Passet togs inte bort eftersom kalenderhändelsen inte kunde tas bort."
            return
        }

        do {
            try repository.delete(shifts)
            earningsViewModel.trackerService.invalidateCache()
        } catch {
            errorMessage = "Passen kunde inte tas bort: \(error.localizedDescription)"
            return
        }

        if earningsViewModel.calendarSync.shouldSynchronize {
            earningsViewModel.calendarSync.recordSyncSucceeded()
        }
    }

    func requestDismissal() {
        if isDirty {
            isDiscardConfirmationPresented = true
        } else {
            closeEditor()
        }
    }

    func discardChanges() {
        closeEditor()
    }

    func changeMonth(by value: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newDate
    }

    func applyPreset(startHour: Int, endHour: Int, breakStartHour: Int?, breakEndHour: Int?) {
        guard let presetStart = calendar.date(
            bySettingHour: startHour,
            minute: 0,
            second: 0,
            of: start
        ) else { return }

        let endDay = endHour < startHour
            ? calendar.date(byAdding: .day, value: 1, to: presetStart) ?? presetStart
            : presetStart

        guard let presetEnd = calendar.date(
            bySettingHour: endHour,
            minute: 0,
            second: 0,
            of: endDay
        ) else { return }

        start = presetStart
        end = presetEnd

        guard let breakStartHour, let breakEndHour else {
            includeBreak = false
            return
        }

        includeBreak = true
        breakPaid = false
        breakStart = calendar.date(
            bySettingHour: breakStartHour,
            minute: 0,
            second: 0,
            of: presetStart
        ) ?? presetStart
        breakEnd = calendar.date(
            bySettingHour: breakEndHour,
            minute: 0,
            second: 0,
            of: presetStart
        ) ?? breakStart
    }

    private var snapshot: Snapshot {
        Snapshot(
            start: start,
            end: end,
            breakStart: breakStart,
            breakEnd: breakEnd,
            breakPaid: breakPaid,
            includeBreak: includeBreak
        )
    }

    private func closeEditor() {
        isEditorPresented = false
        isDiscardConfirmationPresented = false
        editingShiftID = nil
        originalSnapshot = nil
    }
}

private enum CalendarSyncMutationError: LocalizedError {
    case deleteFailed

    var errorDescription: String? {
        "En eller flera kalenderhändelser kunde inte tas bort."
    }
}
