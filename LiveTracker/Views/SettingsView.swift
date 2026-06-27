import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    
    @State private var selectedIndex = 0
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Form {
            PaySettingsManagementSection(
                viewModel: viewModel,
                selectedIndex: $selectedIndex,
                showDeleteConfirmation: $showDeleteConfirmation,
                onNewSetting: createNewPaySetting
            )
            
            Section(header: Text("Gross Hourly Rate"), footer: Text("Enter your gross hourly rate.")) {
                LabeledContent {
                    TextField("0", value: $viewModel.settings[safeIndex].hourlyRate, format: .currency(code: "SEK"))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .onChange(of: viewModel.settings[safeIndex].hourlyRate) { _, _ in
                            viewModel.settings[safeIndex].recalculateRates()
                        }
                } label: {
                    Label("Hourly Rate", systemImage: "banknote")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                }
            }
            
            Section(header: Text("Net rates (per hour)"), footer: VStack(alignment: .leading, spacing: 4) {
                Text("OB supplements:")
                Text("* Evening Mon-Fri 18-00: salary / 600")
            }.font(.caption2)) {
                rateRow(label: Label("Day (07-18)", systemImage: "sun.max.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.yellow), value: $viewModel.settings[safeIndex].dayRate)
                rateRow(label: Label("Evening (18-23)", systemImage: "sunset.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.orange), value: $viewModel.settings[safeIndex].eveningRate)
                rateRow(label: Label("Night (00-07)", systemImage: "moon.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.indigo), value: $viewModel.settings[safeIndex].nightRate)
                rateRow(label: Label("Weekend", systemImage: "sparkles").symbolRenderingMode(.hierarchical).foregroundStyle(.pink), value: $viewModel.settings[safeIndex].weekendRate)
                rateRow(label: Label("Holiday", systemImage: "flag.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.red), value: $viewModel.settings[safeIndex].holidayRateA)
                rateRow(label: Label("Holiday (Major)", systemImage: "star.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.purple), value: $viewModel.settings[safeIndex].holidayRateB)
            }
            
            Section(header: Text("Validity Period"), footer: Text("The date range during which this pay settings applies.")) {
                DatePicker("Start Date", selection: $viewModel.settings[safeIndex].startRange, displayedComponents: .date)
                DatePicker("End Date", selection: $viewModel.settings[safeIndex].endRange, displayedComponents: .date)
            }
            
            Section(footer: Text("Show or hide the earned amount on the main screen.")) {
                Toggle(isOn: $viewModel.showEarned) {
                    Label("Show Earned", systemImage: viewModel.showEarned ? "eye.fill" : "eye.slash.fill")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            "Delete Pay Setting",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentPaySetting() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pay setting will be permanently removed.")
        }
    }
    
    var safeIndex: Int {
        max(0, min(selectedIndex, viewModel.settings.count - 1))
    }
    
    private func rateRow<L: View>(label: L, value: Binding<Double>) -> some View {
        LabeledContent {
            TextField("0", value: value, format: .currency(code: "SEK"))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        } label: {
            label
        }
    }
    
    private func createNewPaySetting() {
        let calendar = Calendar.current
        let now = Date()
        
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) else { return }
        guard let startOfNextMonth = calendar.date(
            from: calendar.dateComponents(
                [.year, .month],
                from: nextMonth
            )
        ) else { return }
        
        if !viewModel.settings.isEmpty {
            let endOfThisMonth = calendar.date(
                byAdding: .day, value: -1, to: startOfNextMonth
            ) ?? now
            viewModel.settings[safeIndex].endRange = endOfThisMonth
        }
        
        let newEnd = calendar.date(byAdding: .year, value: 10, to: startOfNextMonth) ?? startOfNextMonth
        let rate = viewModel.settings.isEmpty ? 0 : viewModel.settings[safeIndex].hourlyRate
        
        var newSetting = PaySettings(startRange: startOfNextMonth, endRange: newEnd)
        newSetting.hourlyRate = rate
        newSetting.recalculateRates()
        
        viewModel.settings.append(newSetting)
        selectedIndex = viewModel.settings.count - 1
    }
    
    private func deleteCurrentPaySetting() {
        guard viewModel.settings.count > 1 else { return }
        let idx = max(0, min(selectedIndex, viewModel.settings.count - 1))
        if idx > 0 {
            let deleted = viewModel.settings[idx]
            viewModel.settings[idx - 1].endRange = deleted.endRange
        }
        viewModel.settings.remove(at: idx)
        selectedIndex = min(idx, viewModel.settings.count - 1)
    }
}

// MARK: - Subviews

struct PaySettingsManagementSection: View {
    @Bindable var viewModel: SettingsViewModel
    @Binding var selectedIndex: Int
    @Binding var showDeleteConfirmation: Bool
    var onNewSetting: () -> Void
    
    var body: some View {
        Section(header: Text("Pay settings"), footer: Text("Each pay setting covers a date range with its own hourly rate.")) {
            Picker("Select", selection: $selectedIndex) {
                ForEach(Array(viewModel.settings.enumerated()), id: \.offset) { index, setting in
                    Text(periodLabel(for: setting)).tag(index)
                }
            }

            Button(action: onNewSetting) {
                Label("New Pay Setting", systemImage: "plus.circle.fill")
            }
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Pay Setting", systemImage: "trash")
            }
            .disabled(viewModel.settings.count <= 1)
        }
    }
    
    private func periodLabel(for setting: PaySettings) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        return "\(fmt.string(from: setting.startRange)) - \(fmt.string(from: setting.endRange))"
    }
}
