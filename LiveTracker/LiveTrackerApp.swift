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
            let modelContainer = try ModelContainer(for: Shift.self)
            self.container = modelContainer
            let dependencies = Self.makeDependencies(modelContainer: modelContainer)
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

    private static func makeDependencies(modelContainer: ModelContainer) -> (settingsVM: SettingsViewModel, earningsVM: EarningsViewModel) {
        let settingsVM = SettingsViewModel()
        let holidayService = HolidayService()
        let calendarService = CalendarManager()
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
        let earningsVM = EarningsViewModel(
            settingsVM: settingsVM,
            shiftRepository: shiftRepository,
            trackerService: trackerService,
            calculator: calculator
        )
        return (settingsVM, earningsVM)
    }

    var body: some Scene {
        WindowGroup {
            if let earningsVM = earningsVM, let settings = settings, let container = container {
                ModernMainView(vm: earningsVM, sm: settings)
                    .modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label("Database Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Could not initialize the local database: \(containerError?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
}
