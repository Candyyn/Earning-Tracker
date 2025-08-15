import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    @State private var dayRateString = ""
    @State private var eveningRateString = ""
    @State private var nightRateString = ""
    @State private var weekendBonusString = ""
    
    var body: some View {
        Form {
            hourlyRatesSection
            weekendBonusSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively) // iOS 16+
        .onAppear(perform: loadValues)
    }
}

// MARK: - Sections
private extension SettingsView {
    var hourlyRatesSection: some View {
        Section {
            currencyLabeledField(
                label: Label("Day (08–18)", systemImage: "sun.max.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow),
                value: $dayRateString,
                binding: $viewModel.settings.dayRate
            )
            
            currencyLabeledField(
                label: Label("Evening (18–23)", systemImage: "sunset.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange),
                value: $eveningRateString,
                binding: $viewModel.settings.eveningRate
            )
            
            currencyLabeledField(
                label: Label("Night (23–08)", systemImage: "moon.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.indigo),
                value: $nightRateString,
                binding: $viewModel.settings.nightRate
            )
        } header: {
            Text("Hourly Rates")
        } footer: {
            Text("Enter your base rates for each time period.")
        }
    }
    
    var weekendBonusSection: some View {
        Section {
            currencyLabeledField(
                label: Label("Weekend Pay", systemImage: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.pink),
                value: $weekendBonusString,
                binding: $viewModel.settings.weekendBonus
            )
        } footer: {
            Text("Applied to all hours worked on Saturdays and Sundays.")
        }
    }
}

// MARK: - Subviews
private extension SettingsView {
    func currencyLabeledField<LabelContent: View>(
        label: LabelContent,
        value: Binding<String>,
        binding: Binding<Double>
    ) -> some View {
        LabeledContent {
            TextField("", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { oldValue, newValue in
                    if let number = Self.currencyFormatter.number(from: newValue) {
                        binding.wrappedValue = number.doubleValue
                    }
                }
        } label: {
            label
        }
    }
}

// MARK: - Helpers
private extension SettingsView {
    func loadValues() {
        dayRateString = Self.currencyFormatter.string(from: NSNumber(value: viewModel.settings.dayRate)) ?? ""
        eveningRateString = Self.currencyFormatter.string(from: NSNumber(value: viewModel.settings.eveningRate)) ?? ""
        nightRateString = Self.currencyFormatter.string(from: NSNumber(value: viewModel.settings.nightRate)) ?? ""
        weekendBonusString = Self.currencyFormatter.string(from: NSNumber(value: viewModel.settings.weekendBonus)) ?? ""
    }
    
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
