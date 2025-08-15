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
            TabView {
                MainView(vm: earningsVM)
                    .tabItem {
                        Label("Main", systemImage: "dollarsign.circle")
                    }
                ShiftView(viewModel: earningsVM)
                    .tabItem {
                        Label("Shifts", systemImage: "calendar")
                    }

                SettingsView(viewModel: settingsVM)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .tabViewStyle(DefaultTabViewStyle()) // Native iOS tab style
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea()
        }
    }
}
