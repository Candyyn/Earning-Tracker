import SwiftUI
import SwiftData

struct ShiftView: View {
    var viewModel: EarningsViewModel
    
    @Query(sort: \Shift.start, order: .forward) private var allShifts: [Shift]
    
    @State private var start = Date()
    @State private var end = Date()
    @State private var breakStart = Date()
    @State private var breakEnd = Date()
    @State private var breakPaid = false
    @State private var includeBreak = false
    
    @State private var editingShiftId: UUID? = nil
    @State private var selectedMonth = Date()
    @State private var syncErrorMessage: String?
    
    var body: some View {
        Form {
            Section {
                NavigationLink(destination: PaySlipVerificationView(earningsViewModel: viewModel)) {
                    Label("Verify Pay Slip", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                }
            }
            
            ShiftFormSection(
                start: $start,
                end: $end,
                breakStart: $breakStart,
                breakEnd: $breakEnd,
                includeBreak: $includeBreak,
                breakPaid: $breakPaid,
                editingShiftId: $editingShiftId,
                onSave: saveShift,
                onReset: resetForm,
                onApplyPreconfigured: applyPreconfiguredShift
            )
            
            ShiftsListSection(
                viewModel: viewModel,
                selectedMonth: $selectedMonth,
                filteredShifts: filteredShifts,
                totalEarnings: totalEarningsForSelectedMonth,
                onChangeMonth: changeMonth,
                onEditShift: editShiftById,
                onDeleteShifts: deleteFilteredShifts
            )
        }
        .navigationTitle("Shifts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                do {
                    try await viewModel.shiftRepository.calendarService.requestAccess()
                    viewModel.importCalendarShifts()
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            viewModel.importCalendarShifts()
        }
        .alert("Shift Sync Problem", isPresented: Binding(
            get: { syncErrorMessage != nil },
            set: { if !$0 { syncErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncErrorMessage ?? "")
        }
    }
}

// MARK: - Computed
private extension ShiftView {
    var filteredShifts: [Shift] {
        let calendar = Calendar.current
        return allShifts.filter { shift in
            calendar.component(.month, from: shift.start) == calendar.component(.month, from: selectedMonth) &&
            calendar.component(.year, from: shift.start) == calendar.component(.year, from: selectedMonth)
        }
    }
    
    var totalEarningsForSelectedMonth: Double {
        viewModel.totalEarningsForShifts(filteredShifts)
    }
}

// MARK: - Actions
private extension ShiftView {
    func saveShift() {
        let newShift = Shift(
            start: start,
            end: end,
            breakStart: includeBreak ? breakStart : nil,
            breakEnd: includeBreak ? breakEnd : nil,
            breakPaid: breakPaid
        )
        
        var existingShift: Shift? = nil
        
        if let id = editingShiftId, let index = allShifts.firstIndex(where: { $0.id == id }) {
            existingShift = allShifts[index]
            newShift.id = existingShift!.id
            newShift.calendarEventId = existingShift!.calendarEventId
        }
        
        do {
            let eventId = try viewModel.shiftRepository.calendarService.save(newShift)
            newShift.calendarEventId = eventId
        } catch {
            syncErrorMessage = "The shift will be saved locally, but calendar sync failed: \(error.localizedDescription)"
        }
        
        if let existing = existingShift {
            existing.start = newShift.start
            existing.end = newShift.end
            existing.breakStart = newShift.breakStart
            existing.breakEnd = newShift.breakEnd
            existing.breakPaid = newShift.breakPaid
            existing.calendarEventId = newShift.calendarEventId
            existing.updateDominantType(holidayService: viewModel.shiftRepository.holidayService)
        } else {
            newShift.updateDominantType(holidayService: viewModel.shiftRepository.holidayService)
            viewModel.modelContext.insert(newShift)
        }
        
        do {
            try viewModel.modelContext.save()
            viewModel.refreshShifts()
            resetForm()
        } catch {
            syncErrorMessage = "The shift could not be saved: \(error.localizedDescription)"
        }
    }
    
    func editShiftById(_ id: UUID) {
        guard let shift = allShifts.first(where: { $0.id == id }) else { return }
        
        start = shift.start
        end = shift.end
        if let bStart = shift.breakStart, let bEnd = shift.breakEnd {
            includeBreak = true
            breakStart = bStart
            breakEnd = bEnd
        } else {
            includeBreak = false
        }
        breakPaid = shift.breakPaid
        editingShiftId = id
    }
    
    func resetForm() {
        start = Date()
        end = Date()
        includeBreak = false
        breakPaid = false
        editingShiftId = nil
    }
    
    func deleteFilteredShifts(at offsets: IndexSet) {
        let shiftsToDelete = offsets.map { filteredShifts[$0] }
        
        for shift in shiftsToDelete {
            do {
                try viewModel.shiftRepository.calendarService.delete(shift)
            } catch {
                syncErrorMessage = "The shift will be deleted locally, but calendar deletion failed: \(error.localizedDescription)"
            }
            viewModel.modelContext.delete(shift)
        }
        do {
            try viewModel.modelContext.save()
            viewModel.refreshShifts()
        } catch {
            syncErrorMessage = "The shift could not be deleted: \(error.localizedDescription)"
        }
    }
    
    func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    func applyPreconfiguredShift(startHour: Int, endHour: Int, breakStartHour: Int?, breakEndHour: Int?) {
        let calendar = Calendar.current
        let now = start // use the currently selected day instead of today
        
        if let s = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now) {
            start = s
        }
        
        var e = now
        if endHour < startHour {
            // cross midnight
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: now) {
                e = nextDay
            }
        }
        if let eFinal = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: e) {
            end = eFinal
        }
        
        if let bStart = breakStartHour, let bEnd = breakEndHour {
            includeBreak = true
            breakPaid = false
            if let bs = calendar.date(bySettingHour: bStart, minute: 0, second: 0, of: now) {
                breakStart = bs
            }
            if let be = calendar.date(bySettingHour: bEnd, minute: 0, second: 0, of: now) {
                breakEnd = be
            }
        } else {
            includeBreak = false
        }
    }
}

// MARK: - Extracted Components

struct ShiftFormSection: View {
    @Binding var start: Date
    @Binding var end: Date
    @Binding var breakStart: Date
    @Binding var breakEnd: Date
    @Binding var includeBreak: Bool
    @Binding var breakPaid: Bool
    @Binding var editingShiftId: UUID?
    
    var onSave: () -> Void
    var onReset: () -> Void
    var onApplyPreconfigured: (Int, Int, Int?, Int?) -> Void
    
    var body: some View {
        Section(header: Text(editingShiftId == nil ? "New Shift" : "Edit Shift")) {
            let maxTimeBetween = 24 * 60 * 60
            
            DatePicker("Start Time", selection: $start, displayedComponents: [.date, .hourAndMinute])
                .onChange(of: start) { oldValue, newValue in
                    if end > newValue.addingTimeInterval(TimeInterval(maxTimeBetween)) {
                        end = newValue.addingTimeInterval(TimeInterval(maxTimeBetween))
                    }
                    if end < newValue {
                        end = newValue
                    }
                }
            DatePicker("End Time", selection: $end, displayedComponents: [.date, .hourAndMinute])
            
            Toggle("Add Break", isOn: $includeBreak.animation())
            
            if includeBreak {
                DatePicker("Break Start", selection: $breakStart, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: breakStart) { oldValue, newValue in
                        if breakEnd > newValue.addingTimeInterval(TimeInterval(maxTimeBetween)) {
                            breakEnd = newValue.addingTimeInterval(TimeInterval(maxTimeBetween))
                        }
                        if breakEnd < newValue {
                            breakEnd = newValue
                        }
                    }
                DatePicker("Break End", selection: $breakEnd, displayedComponents: [.date, .hourAndMinute])
                Toggle("Paid Break", isOn: $breakPaid)
            }
            
            if editingShiftId == nil {
                HStack {
                    Button("Day Shift") {
                        onApplyPreconfigured(8, 17, 12, 13)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Evening Shift") {
                        onApplyPreconfigured(16, 23, nil, nil)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
                
                Button(action: onSave) {
                    Label("Add Shift", systemImage: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                }
                .disabled(!isValidShift)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack {
                    Button(action: onSave) {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                    .disabled(!isValidShift)
                    .frame(maxWidth: .infinity)
                    
                    Button(role: .destructive, action: onReset) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var isValidShift: Bool {
        guard end > start else { return false }
        guard includeBreak else { return true }
        return breakStart >= start && breakEnd <= end && breakEnd > breakStart
    }
}

struct ShiftsListSection: View {
    var viewModel: EarningsViewModel
    @Binding var selectedMonth: Date
    var filteredShifts: [Shift]
    var totalEarnings: Double
    var onChangeMonth: (Int) -> Void
    var onEditShift: (UUID) -> Void
    var onDeleteShifts: (IndexSet) -> Void
    
    var body: some View {
        Group {
            if filteredShifts.isEmpty {
                Section(header: monthHeader) {
                    Text("No shifts this month")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(header: monthHeader) {
                    ForEach(filteredShifts) { shift in
                        ShiftCard(shift: shift, viewModel: viewModel)
                            .equatable()
                            .contentShape(Rectangle())
                            .onTapGesture { onEditShift(shift.id) }
                    }
                    .onDelete(perform: onDeleteShifts)
                    
                    let hours = viewModel.workedHoursByType(for: filteredShifts)
                    HoursSummaryView(
                        dayHours: hours.day,
                        eveningHours: hours.evening,
                        nightHours: hours.night,
                        weekendHours: hours.weekend,
                        holidayHours: hours.holiday,
                        holidayMajorHours: hours.holidayMajor,
                        totalHours: hours.total
                    )
                    
                    HStack {
                        Spacer()
                        Text("Total earned: \(totalEarnings, format: .currency(code: "SEK"))")
                            .font(.headline)
                            .privacySensitive()
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    var monthHeader: some View {
        HStack {
            Button { onChangeMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(selectedMonth, format: .dateTime.month().year())
                .font(.headline)
            Spacer()
            Button { onChangeMonth(1) } label: { Image(systemName: "chevron.right") }
        }
    }
}

struct HoursSummaryView: View {
    let dayHours: Double
    let eveningHours: Double
    let nightHours: Double
    let weekendHours: Double
    let holidayHours: Double
    let holidayMajorHours: Double
    let totalHours: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hours Summary").font(.headline).padding(.bottom, 4)
            HStack { Text("Day Hours:"); Spacer(); Text("\(dayHours, specifier: "%.2f") h") }
            HStack { Text("Evening Hours:"); Spacer(); Text("\(eveningHours, specifier: "%.2f") h") }
            HStack { Text("Night Hours:"); Spacer(); Text("\(nightHours, specifier: "%.2f") h") }
            HStack { Text("Weekend Hours:"); Spacer(); Text("\(weekendHours, specifier: "%.2f") h") }
            HStack { Text("Holiday Hours:"); Spacer(); Text("\(holidayHours, specifier: "%.2f") h") }
            HStack { Text("Holiday (Major) Hours:"); Spacer(); Text("\(holidayMajorHours, specifier: "%.2f") h") }
            Divider()
            HStack {
                Text("Total Hours:").fontWeight(.bold)
                Spacer()
                Text("\(totalHours, specifier: "%.2f") h").fontWeight(.bold)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.vertical, 8)
    }
}
