//
//  LiveTrackerApp.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import SwiftUI
import SwiftData

@main
struct LiveTrackerApp: App {
    @State private var settings: SettingsViewModel?
    @State private var earningsVM: EarningsViewModel?
    @State private var containerError: Error?
    
    let container: ModelContainer?

    init() {
        do {
            let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
            let modelContainer = try ModelContainer(for: Shift.self, configurations: configuration)
            let defaults: UserDefaults
            if isUITesting {
                let suiteName = "LiveTracker.UITesting"
                defaults = UserDefaults(suiteName: suiteName) ?? .standard
                defaults.removePersistentDomain(forName: suiteName)
            } else {
                defaults = .standard
            }

            let dependencies = Self.makeDependencies(modelContainer: modelContainer, defaults: defaults)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-seeded") {
                try Self.seedUITestData(
                    modelContext: modelContainer.mainContext,
                    settings: dependencies.settingsVM,
                    holidayService: dependencies.earningsVM.shiftRepository.holidayService
                )
            }
            self.container = modelContainer
            _settings = State(wrappedValue: dependencies.settingsVM)
            _earningsVM = State(wrappedValue: dependencies.earningsVM)
            self.containerError = nil
        } catch {
            self.container = nil
            self.containerError = error
            _settings = State(initialValue: nil)
            _earningsVM = State(initialValue: nil)
        }
    }

    private static func makeDependencies(
        modelContainer: ModelContainer,
        defaults: UserDefaults
    ) -> (settingsVM: SettingsViewModel, earningsVM: EarningsViewModel) {
        let settingsVM = SettingsViewModel(defaults: defaults)
        let holidayService = HolidayService()
        let calendarService = CalendarManager()
        let calendarSync = CalendarSyncCoordinator(calendarService: calendarService, defaults: defaults)
        let shiftRepository = ShiftRepository(
            modelContext: modelContainer.mainContext,
            holidayService: holidayService,
            calendarService: calendarService
        )
        let calculator = EarningsCalculator(holidayService: holidayService)
        let trackerService = EarningsTrackerService(
            shiftRepository: shiftRepository,
            calculator: calculator,
            settingsVM: settingsVM
        )
        settingsVM.setChangeHandler { [weak trackerService] in
            trackerService?.invalidateCache()
        }
        let earningsVM = EarningsViewModel(
            settingsVM: settingsVM,
            shiftRepository: shiftRepository,
            trackerService: trackerService,
            calculator: calculator,
            calendarSync: calendarSync,
            legacyDefaults: defaults
        )
        return (settingsVM, earningsVM)
    }

    private static func seedUITestData(
        modelContext: ModelContext,
        settings: SettingsViewModel,
        holidayService: HolidayProviding
    ) throws {
        if let id = settings.settings.first?.id {
            settings.updateHourlyRate(for: id, to: 185)
        }

        let calendar = SwedishMarket.calendar
        let day = calendar.startOfDay(for: .now)
        guard let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day),
              let breakStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
              let breakEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day) else {
            return
        }

        let shift = Shift(
            start: start,
            end: end,
            breakStart: breakStart,
            breakEnd: breakEnd,
            breakPaid: false
        )
        shift.updateDominantType(holidayService: holidayService)
        modelContext.insert(shift)
        try modelContext.save()
    }

    var body: some Scene {
        WindowGroup {
            if let earningsVM = earningsVM, let settings = settings, let container = container {
                ModernMainView(vm: earningsVM, sm: settings)
                    .modelContainer(container)
                    .environment(\.locale, SwedishMarket.locale)
                    .environment(\.calendar, SwedishMarket.calendar)
                    .environment(\.timeZone, SwedishMarket.timeZone)
            } else {
                ContentUnavailableView {
                    Label("Databasfel", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Den lokala databasen kunde inte startas: \(containerError?.localizedDescription ?? "Okänt fel")")
                }
            }
        }
    }
}
