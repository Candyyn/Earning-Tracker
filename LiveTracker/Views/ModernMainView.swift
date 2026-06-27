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
        let progress = min(vm.currentEarnings / 25000.0, 1.0)
        EarningsAuraView(shiftType: vm.currentType(for: Date()), progress: progress)
    }
}

struct EarningsDisplayView: View {
    var vm: EarningsViewModel
    var currentSettings: PaySettings
    
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Earnings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Text("\(currentSettings.showEarned ? (ModernMainView.currencyFormatter.string(from: vm.currentEarnings as NSNumber) ?? "") : "***,**")")
                .contentTransition(.numericText(value: vm.currentEarnings))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .animation(.easeInOut(duration: 0.2), value: vm.currentEarnings)
                .foregroundStyle(.primary)
                .privacySensitive()
            
            TextShimmer(vm: vm, duration: 2)
                .font(.subheadline)
        }
    }
}

struct ModernMainView: View {
    var vm: EarningsViewModel
    var sm: SettingsViewModel
    
    @State private var showSettings = false
    @State private var showShifts = false
    
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "kr"
        return formatter
    }()
    
    var body: some View {
        let currentSettings = sm.paySettings(for: Date()) ?? sm.settings.first ?? PaySettings(startRange: Date(), endRange: Date())
        
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
                EarningsDisplayView(vm: vm, currentSettings: currentSettings)
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
                            .accessibilityLabel("Shifts")
                    }
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 65, height: 65)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .accessibilityLabel("Settings")
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(viewModel: sm)
                    .toolbar {
                        ToolbarItem {
                            Button("Done") { showSettings.toggle() }
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
                            Button("Done") { showShifts.toggle() }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.automatic)
            .presentationBackground(.regularMaterial)
        }
    }
}
