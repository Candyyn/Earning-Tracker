//
//  ModernMainView.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-10-01.
//

import SwiftUI


struct EarningsAuraWrapper: View {
    var vm: EarningsViewModel
    
    var body: some View {
        let progress = min(vm.currentEarnings.doubleValue / 25000.0, 1.0)
        EarningsAuraView(shiftType: vm.currentType(for: Date()), progress: progress)
    }
}

struct EarningsDisplayView: View {
    var vm: EarningsViewModel
    let showsEarnings: Bool
    
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Intjänat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Text(showsEarnings ? formattedEarnings : "***,**")
                .contentTransition(.numericText(value: vm.currentEarnings.doubleValue))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .animation(.easeInOut(duration: 0.2), value: vm.currentEarnings)
                .foregroundStyle(.primary)
                .privacySensitive()
            
            TextShimmer(vm: vm, duration: 2)
                .font(.subheadline)
        }
    }

    private var formattedEarnings: String {
        SwedishMarket.currencyWithOre(vm.currentEarnings)
    }
}

struct ModernMainView: View {
    var vm: EarningsViewModel
    var sm: SettingsViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showShifts = false
    
    var body: some View {
        ZStack {
            // Background Aura
            EarningsAuraWrapper(vm: vm)
                .ignoresSafeArea()
            
            // Glass overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                Spacer()
                
                // Central Glass Capsule
                EarningsDisplayView(vm: vm, showsEarnings: sm.showEarned)
                    .padding(.vertical, 40)
                
                Spacer()
                
                // Floating Action Buttons
                HStack(spacing: 40) {
                    Button(action: { showShifts.toggle() }) {
                        Image(systemName: "calendar")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 65, height: 65)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .accessibilityLabel("Arbetspass")
                    }
                    .accessibilityIdentifier("dashboard.shifts")

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 65, height: 65)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .accessibilityLabel("Inställningar")
                    }
                    .accessibilityIdentifier("dashboard.settings")
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(viewModel: sm, earningsViewModel: vm)
                    .toolbar {
                        ToolbarItem {
                            Button("Klar") { showSettings.toggle() }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.automatic)
            .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $showShifts) {
            NavigationStack {
                ShiftView(viewModel: vm)
                    .toolbar {
                        ToolbarItem {
                            Button("Klar") { showShifts.toggle() }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.automatic)
            .presentationBackground(.regularMaterial)
        }
        .task {
            vm.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                vm.start()
            case .inactive, .background:
                vm.stop()
            @unknown default:
                vm.stop()
            }
        }
        .alert("Dataproblem", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
