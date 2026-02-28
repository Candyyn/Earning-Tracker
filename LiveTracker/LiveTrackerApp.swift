//
//  LiveTrackerApp.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import SwiftUI

@main
struct LiveEarningsApp: App {
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var earningsVM: EarningsViewModel

    init() {
        // Ensure shared SettingsViewModel and EarningsViewModel
        let settings = SettingsViewModel()
        _settingsVM = StateObject(wrappedValue: settings)
        _earningsVM = StateObject(wrappedValue: EarningsViewModel(settingsVM: settings))
    }

    var body: some Scene {
        WindowGroup {
            MainView(vm: earningsVM, sm: settingsVM)
            .background(Color(.systemBackground))
            
        }
    }
}
