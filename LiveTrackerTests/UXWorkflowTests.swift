import Foundation
import SwiftData
import Testing
@testable import LiveTracker

@MainActor
@Suite(.serialized)
struct UXWorkflowTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func payPeriodCreationAndDeletionKeepRangesContinuous() throws {
        let defaults = makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)
        let originalID = try #require(viewModel.settings.first?.id)
        let originalEnd = try #require(viewModel.settings.first?.endRange)
        viewModel.updateHourlyRate(for: originalID, to: 200)

        let referenceDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let newID = try #require(viewModel.createPayPeriod(referenceDate: referenceDate, calendar: calendar))
        let newPeriod = try #require(viewModel.settings.first(where: { $0.id == newID }))
        let previousPeriod = try #require(viewModel.settings.first(where: { $0.id == originalID }))

        #expect(calendar.component(.month, from: newPeriod.startRange) == 7)
        #expect(previousPeriod.endRange == newPeriod.startRange)
        #expect(newPeriod.endRange == originalEnd)
        #expect(newPeriod.hourlyRate == 200)

        viewModel.deletePayPeriod(id: newID)

        #expect(viewModel.settings.count == 1)
        #expect(viewModel.settings[0].endRange == originalEnd)
    }

    @Test func hourlyRateChangesRecalculateReadOnlyRates() throws {
        let viewModel = SettingsViewModel(defaults: makeDefaults())
        let id = try #require(viewModel.settings.first?.id)

        viewModel.updateHourlyRate(for: id, to: 180)
        let setting = try #require(viewModel.settings.first)

        #expect(setting.dayRate > 0)
        #expect(setting.eveningRate > setting.dayRate)
        #expect(setting.nightRate > setting.eveningRate)
        #expect(setting.holidayRateB > setting.holidayRateA)
    }

    @Test func calendarSyncRequiresExplicitOptIn() async throws {
        let service = MockCalendarService()
        let coordinator = CalendarSyncCoordinator(calendarService: service, defaults: makeDefaults())
        var operationCount = 0

        try await coordinator.performSync {
            operationCount += 1
        }
        #expect(operationCount == 0)
        #expect(coordinator.state == .disconnected)

        try await coordinator.connect()
        try await coordinator.performSync {
            operationCount += 1
        }

        #expect(operationCount == 1)
        #expect(coordinator.state == .connected)
    }

    @Test func shiftEditorValidatesPresetsAndDirtyState() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)))
        let dependencies = try makeDependencies(now: now)
        let editor = ShiftEditorViewModel(
            earningsViewModel: dependencies.viewModel,
            calendar: calendar,
            now: { now }
        )

        editor.presentNewShift()
        #expect(editor.isValid)
        #expect(!editor.isDirty)

        editor.applyPreset(startHour: 22, endHour: 7, breakStartHour: nil, breakEndHour: nil)
        #expect(editor.end > editor.start)
        #expect(editor.isDirty)

        editor.includeBreak = true
        editor.breakStart = editor.end
        editor.breakEnd = editor.start
        #expect(!editor.isValid)
        #expect(editor.validationMessage != nil)
    }

    @Test func repositoryRefreshesWhenTheCalendarMonthChanges() throws {
        let june = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15)
        ))
        let july = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 1)
        ))
        let dependencies = try makeDependencies(now: june)
        let repository = dependencies.viewModel.shiftRepository

        let initialRefresh = try repository.refreshShiftsIfMonthChanged(
            referenceDate: june,
            calendar: calendar
        )
        let repeatedRefresh = try repository.refreshShiftsIfMonthChanged(
            referenceDate: june,
            calendar: calendar
        )
        let nextMonthRefresh = try repository.refreshShiftsIfMonthChanged(
            referenceDate: july,
            calendar: calendar
        )

        #expect(initialRefresh)
        #expect(!repeatedRefresh)
        #expect(nextMonthRefresh)
    }

    @Test func failedCalendarSavePreservesTheExistingEventIdentifier() async throws {
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)
        ))
        let dependencies = try makeDependencies(now: now)
        try await dependencies.viewModel.calendarSync.connect()

        let shift = Shift(
            start: now,
            end: now.addingTimeInterval(8 * 60 * 60),
            calendarEventId: "existing-event"
        )
        try dependencies.viewModel.shiftRepository.insert(shift)

        let editor = ShiftEditorViewModel(
            earningsViewModel: dependencies.viewModel,
            calendar: calendar,
            now: { now }
        )
        editor.edit(shift)
        editor.end = editor.end.addingTimeInterval(60 * 60)
        dependencies.calendarService.saveError = CalendarTestError.saveFailed

        editor.save(allShifts: [shift])

        #expect(shift.calendarEventId == "existing-event")
        #expect(editor.errorMessage != nil)
    }

    @Test func calendarSyncMatchesCrossBoundaryShiftByStableIdentifier() async throws {
        let intervalStart = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1)
        ))
        let shiftStart = try #require(calendar.date(byAdding: .hour, value: -2, to: intervalStart))
        let shiftEnd = try #require(calendar.date(byAdding: .hour, value: 6, to: intervalStart))
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Shift.self, configurations: configuration)
        let existing = Shift(
            start: shiftStart,
            end: shiftEnd,
            calendarEventId: "old-event",
            calendarSyncIdentifier: "eventkit:stable"
        )
        container.mainContext.insert(existing)
        try container.mainContext.save()

        let fetched = CalendarShift(
            id: UUID(),
            start: shiftStart,
            end: shiftEnd.addingTimeInterval(3600),
            breakStart: nil,
            breakEnd: nil,
            breakPaid: false,
            calendarEventID: "new-event",
            syncIdentifier: "eventkit:stable"
        )
        let record = ShiftSyncRecord(
            calendarShift: fetched,
            dominantShiftType: .night
        )
        let actor = ShiftSyncActor(modelContainer: container)

        try await actor.syncCalendarShifts(
            [record],
            from: intervalStart,
            to: try #require(calendar.date(byAdding: .month, value: 1, to: intervalStart))
        )

        let shifts = try container.mainContext.fetch(FetchDescriptor<Shift>())
        #expect(shifts.count == 1)
        #expect(shifts[0].id == existing.id)
        #expect(shifts[0].calendarEventId == "new-event")
    }

    private func makeDependencies(now: Date) throws -> (
        viewModel: EarningsViewModel,
        calendarService: MockCalendarService
    ) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Shift.self, configurations: configuration)
        let calendarService = MockCalendarService()
        let defaults = makeDefaults()
        let settings = SettingsViewModel(defaults: defaults)
        let holidays = HolidayService()
        let repository = ShiftRepository(
            modelContext: container.mainContext,
            holidayService: holidays,
            calendarService: calendarService
        )
        let calculator = EarningsCalculator(holidayService: holidays)
        let tracker = EarningsTrackerService(
            shiftRepository: repository,
            calculator: calculator,
            settingsVM: settings,
            calendar: calendar,
            now: { now }
        )
        let coordinator = CalendarSyncCoordinator(calendarService: calendarService, defaults: defaults)
        let viewModel = EarningsViewModel(
            settingsVM: settings,
            shiftRepository: repository,
            trackerService: tracker,
            calculator: calculator,
            calendarSync: coordinator
        )
        return (viewModel, calendarService)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LiveTrackerTests.\(UUID().uuidString)")!
    }
}

private enum CalendarTestError: Error {
    case saveFailed
}
