import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    @State private var HourlyPay = ""
    
    @State private var dayRateString = ""
    @State private var eveningRateString = ""
    @State private var nightRateString = ""
    @State private var weekendBonusString = ""
    
    @State private var taxRateString = ""
    @State private var holidayBonusString = ""
    
    @State private var selectedIndex: Int = 0
    @State private var selectedVM: PaySettings? = nil;
    @State private var dates: Set<DateComponents> = []
    
    @State private var editableStartDate: Date = Date()
    @State private var editableEndDate: Date = Date()
    
    
    var body: some View {
        Form {
            paySettingsManagementSection
            hourlyRatesSection
            weekendBonusSection
            displayOptionsSection
            hourlyRateRange
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively) // iOS 16+
        .onAppear(perform: loadValues)
    }
}

// MARK: - Sections
private extension SettingsView {
    
    var paySettingsManagementSection: some View {
        Section("Pay Settings") {
            Picker("Select", selection: $selectedIndex) {
                ForEach(Array(viewModel.settings.enumerated()), id: \.offset) { index, setting in
                    // Display a friendly label with range
                    let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: setting.startRange)) ?? setting.startRange
                    let end = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: setting.endRange)) ?? setting.endRange
                    Text("\(formattedYearMonth(start)) – \(formattedYearMonth(end))").tag(index)
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                print("Index: \(newIndex), count: \(viewModel.settings.count)")
                
                guard newIndex >= 0 && newIndex < viewModel.settings.count else { return }
                let selected = viewModel.settings[newIndex]
                loadValues()
            }

            Button {
                createNewPaySetting()
            } label: {
                Label("New Pay Setting", systemImage: "plus.circle.fill")
            }
            Button(role: .destructive) {
                deleteCurrentPaySetting()
            } label: {
                Label("Delete Pay Setting", systemImage: "trash")
            }
            .disabled(viewModel.settings.count <= 1)
        }
    }
    
    func formattedYearMonth(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        return fmt.string(from: date)
    }
    
    func deleteCurrentPaySetting() {
        guard viewModel.settings.count > 1 else { return }
        
        let idx = max(0, min(selectedIndex, viewModel.settings.count - 1))
        
        // If deleting a middle item, extend the previous one to cover its range
        if idx > 0 {
            let deleted = viewModel.settings[idx]
            viewModel.settings[idx - 1].endRange = deleted.endRange
        }
        
        viewModel.settings.remove(at: idx)
        
        // Adjust selected index safely
        selectedIndex = min(idx, viewModel.settings.count - 1)
        
        editableStartDate = viewModel.settings[selectedIndex].startRange
        editableEndDate = viewModel.settings[selectedIndex].endRange
    }

    func createNewPaySetting() {
        guard !viewModel.settings.isEmpty else {
            // If no settings, create a default spanning next month for 10 years
            let now = Date()
            let calendar = Calendar.current
            let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: now)!))!
            let endDate = calendar.date(byAdding: .year, value: 10, to: startOfNextMonth) ?? startOfNextMonth
            let new = PaySettings(dayRate: 0, eveningRate: 0, nightRate: 0, weekendBonus: 0, showEarned: true, startRange: startOfNextMonth, endRange: endDate)
            viewModel.settings.append(new)
            selectedIndex = viewModel.settings.count - 1
            editableStartDate = new.startRange
            editableEndDate = new.endRange
            loadValues()
            return
        }
        let calendar = Calendar.current
        // Current selected setting
        let idx = max(0, min(selectedIndex, viewModel.settings.count - 1))
        var current = viewModel.settings[idx]
        let now = Date()
        // End current at end of this month
        let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: now)!))!
        let endOfThisMonth = calendar.date(byAdding: .day, value: -1, to: startOfNextMonth) ?? now
        current.endRange = endOfThisMonth
        viewModel.settings[idx] = current
        // New setting starts next month and ends 10 years later
        let newEnd = calendar.date(byAdding: .year, value: 10, to: startOfNextMonth) ?? startOfNextMonth
        let new = PaySettings(dayRate: current.dayRate, eveningRate: current.eveningRate, nightRate: current.nightRate, weekendBonus: current.weekendBonus, showEarned: current.showEarned, startRange: startOfNextMonth, endRange: newEnd)
        viewModel.settings.append(new)
        selectedIndex = viewModel.settings.count - 1
        editableStartDate = new.startRange
        editableEndDate = new.endRange
    }
    
    func changeMonth(by value: Int) {
        let newIndex = selectedIndex + value
        guard newIndex >= 0, newIndex < viewModel.settings.count else { return }
        selectedIndex = newIndex
        // Sync editable dates to the newly selected range
        let selectedPayRange = viewModel.settings[selectedIndex]
        editableStartDate = selectedPayRange.startRange
        editableEndDate = selectedPayRange.endRange
    }
    
    var hourlyRateRange: some View {
        
        Section {
            DatePicker(
                selection: Binding<Date>(
                    get: { editableStartDate },
                    set: { newValue in
                        editableStartDate = newValue
                        viewModel.settings[selectedIndex].startRange = newValue
                    }
                ),
                displayedComponents: .date
            ) {
                Text("Start Time")
            }
            
            DatePicker(
                selection: Binding<Date>(
                    get: { editableEndDate },
                    set: { newValue in
                        editableEndDate = newValue
                        viewModel.settings[selectedIndex].endRange = newValue
                    }
                ),
                displayedComponents: [.date]
            ) {
                Text("End Time")
            }
            
            
        } footer: {
            Text("Toggle to show or hide the earned amount in the main view.")
        }

    }
    
    var hourlyRatesSection: some View {
        Section {
            currencyLabeledField(
                label: Label("Hourly Pay", systemImage: "sun.max.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow),
                value: $HourlyPay,
                binding: $viewModel.settings[selectedIndex].HourlyPay,
                onValueChange: { number in
                    
                    let eveningBonus: Double = 47.32
                    let weekendBonus: Double = 94.63
                    let nightBonus: Double = 70.98
                    let vacationBonusRate: Double = 0.125
                    let taxRate: Double = 0.3
                    
                    func netForOneHour(rate: Double) -> Double {
                            let base = rate
                            let vacation = base * vacationBonusRate
                            
                            let taxBase = floor(base * taxRate)
                            let taxVacation = floor(vacation * taxRate)
                            
                        return round(base + vacation - taxBase - taxVacation)
                    }
                        
                    let eveningRate = number.doubleValue + eveningBonus
                    let weekendRate = number.doubleValue + weekendBonus
                    let nightRate = number.doubleValue + nightBonus
                    
                    let nettoDay = netForOneHour(rate: number.doubleValue);
                    let nettoEvening = netForOneHour(rate: eveningRate);
                    let nettoNight = netForOneHour(rate: nightRate);
                    let nettoWeekend = netForOneHour(rate: weekendRate);
                    

                    // Update UI strings
                    self.dayRateString = Self.currencyString(from: nettoDay)
                    self.eveningRateString = Self.currencyString(from: nettoEvening)
                    self.nightRateString = Self.currencyString(from: nettoNight)
                    self.weekendBonusString = Self.currencyString(from: nettoWeekend)

                    // Persist into selected PaySettings if available
                    if !self.viewModel.settings.isEmpty {
                        let idx = max(0, min(self.selectedIndex, self.viewModel.settings.count - 1))
                        var current = self.viewModel.settings[idx]
                        current.dayRate = nettoDay
                        current.eveningRate = nettoEvening
                        current.nightRate = nettoNight
                        current.weekendBonus = nettoWeekend
                        self.viewModel.settings[idx] = current
                    }
                }
            )
            
            
            currencyLabeledField(
                label: Label("Day (08–18)", systemImage: "sun.max.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow),
                value: $dayRateString,
                binding: $viewModel.settings[selectedIndex].dayRate
            )
            
            currencyLabeledField(
                label: Label("Evening (18–24)", systemImage: "sunset.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange),
                value: $eveningRateString,
                binding: $viewModel.settings[selectedIndex].eveningRate
            )
            
            currencyLabeledField(
                label: Label("Night (24–08)", systemImage: "moon.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.indigo),
                value: $nightRateString,
                binding: $viewModel.settings[selectedIndex].nightRate
            )
        
            
            //RateLabeledField(
            //    label: Label("Tax Rate", systemImage: "moon.fill")
            //        .symbolRenderingMode(.hierarchical)
            //        .foregroundStyle(.indigo),
            //    value: $taxRateString,
            //    binding: $viewModel.settings.nightRate
           // )
            
        } header: {
            Text("Hourly Rates")
        } footer: {
            Text("Enter your base rates for each time period.")
        }
    }
    
    var displayOptionsSection: some View {
            Section {
                Toggle(isOn: $viewModel.settings[0].showEarned) {
                    Label("Show Earned", systemImage: "eye.fill")
                }
            } footer: {
                Text("Toggle to show or hide the earned amount in the main view.")
            }
        }
    
    var weekendBonusSection: some View {
        Section {
            currencyLabeledField(
                label: Label("Weekend Pay", systemImage: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.pink),
                value: $weekendBonusString,
                binding: $viewModel.settings[selectedIndex].weekendBonus
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
        binding: Binding<Double>,
        onValueChange: ((NSNumber) -> Void)? = nil,
    ) -> some View {
        LabeledContent {
            TextField("", text: value)
                /*.keyboardType(.decimalPad)*/
                .submitLabel(.done)
            
                
                .onSubmit {
                        if let number = Self.currencyFormatter.number(from: value.wrappedValue) {
                            binding.wrappedValue = number.doubleValue
                            onValueChange?(number)
                        }
                    }
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { oldValue, newValue in
                    /*if let number = Self.currencyFormatter.number(from: newValue) {
                        binding.wrappedValue = number.doubleValue
                        if(onValueChange != nil) {
                            onValueChange?(number)
                        }
                        
                    }*/
                    
                }
        } label: {
            label
        }
    }
    
    func RateLabeledField<LabelContent: View>(
        label: LabelContent,
        value: Binding<String>,
        binding: Binding<Double>
    ) -> some View {
        LabeledContent {
            TextField("", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        } label: {
            label
        }
    }
}

// MARK: - Helpers
private extension SettingsView {
    static func currencyString(from value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? ""
    }
    
    func loadValues() {
        if(selectedIndex < 0) {
            selectedIndex = viewModel.settings.count - 1
        }
        HourlyPay = Self.currencyString(from: 0)
        dayRateString = Self.currencyString(from: 0)
        eveningRateString = Self.currencyString(from: 0)
        nightRateString = Self.currencyString(from: 0)
        weekendBonusString = Self.currencyString(from: 0)
        if viewModel.settings.isEmpty {
            selectedIndex = 0
        } else {
            
            let selected = viewModel.settings[selectedIndex]
            editableStartDate = selected.startRange
            editableEndDate = selected.endRange
            HourlyPay = Self.currencyString(from: selected.HourlyPay)
            dayRateString = Self.currencyString(from: selected.dayRate)
            eveningRateString = Self.currencyString(from: selected.eveningRate)
            nightRateString = Self.currencyString(from: selected.nightRate)
            weekendBonusString = Self.currencyString(from: selected.weekendBonus)
        }
    }
    
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

