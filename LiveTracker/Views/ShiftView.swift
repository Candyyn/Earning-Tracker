import SwiftUI

struct ShiftView: View {
    @ObservedObject var viewModel: EarningsViewModel
    
    @State private var start = Date()
    @State private var end = Date()
    @State private var breakStart = Date()
    @State private var breakEnd = Date()
    @State private var breakPaid = false
    @State private var includeBreak = false
    
    @State private var editingShiftIndex: Int? = nil
    @State private var selectedMonth = Date()
    
    var body: some View {
        Form {
            shiftFormSection
            shiftsListSection
        }
        .navigationTitle("Shifts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sections
private extension ShiftView {
    var shiftFormSection: some View {
        Section(header: Text(editingShiftIndex == nil ? "New Shift" : "Edit Shift")) {
            DatePicker("Start Time", selection: $start, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End Time", selection: $end, displayedComponents: [.date, .hourAndMinute])
            
            Toggle("Add Break", isOn: $includeBreak.animation())
            
            if includeBreak {
                DatePicker("Break Start", selection: $breakStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Break End", selection: $breakEnd, displayedComponents: [.date, .hourAndMinute])
                Toggle("Paid Break", isOn: $breakPaid)
            }
            
            if editingShiftIndex == nil {
                addShiftButton
            } else {
                editShiftButtons
            }
        }
    }
    
    var shiftsListSection: some View {
        Group {
            if filteredShifts.isEmpty {
                Section(header: monthHeader) {
                    Text("No shifts this month")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(header: monthHeader) {
                    ForEach(Array(filteredShifts.enumerated()), id: \.element.id) { index, shift in
                        shiftRow(for: shift)
                            .onTapGesture { editShiftById(shift.id) }
                    }
                    .onDelete(perform: deleteFilteredShifts)
                    
                    if selectedMonth < Calendar.current.startOfMonth(for: Date()) {
                        monthTotalRow
                    }
                }
            }
        }
    }
}

// MARK: - Subviews
private extension ShiftView {
    var addShiftButton: some View {
        Button(action: saveShift) {
            Label("Add Shift", systemImage: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    var editShiftButtons: some View {
        HStack {
            Button(action: saveShift) {
                Label("Save Changes", systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
            
            Button(role: .destructive, action: resetForm) {
                Label("Cancel", systemImage: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(selectedMonth, format: .dateTime.month().year())
                .font(.headline)
            Spacer()
            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    func shiftRow(for shift: Shift) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.formatShiftDate(shift))
                .font(.headline)
            if let breakText = Self.formatBreak(shift) {
                Text(breakText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
    
    var monthTotalRow: some View {
        HStack {
            Spacer()
            Text("Total earned: \(totalEarningsForSelectedMonth, format: .currency(code: "SEK"))")
                .font(.headline)
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Computed
private extension ShiftView {
    var filteredShifts: [Shift] {
        let calendar = Calendar.current
        return viewModel.shifts.filter { shift in
            calendar.component(.month, from: shift.start) == calendar.component(.month, from: selectedMonth) &&
            calendar.component(.year, from: shift.start) == calendar.component(.year, from: selectedMonth)
        }
    }
    
    var totalEarningsForSelectedMonth: Double {
        return filteredShifts.reduce(0) { total, shift in
            var segments: [(Date, Date)] = [(shift.start, shift.end)]
            
            if let bStart = shift.breakStart, let bEnd = shift.breakEnd, !shift.breakPaid {
                segments = []
                if shift.start < bStart {
                    segments.append((shift.start, bStart))
                }
                if shift.end > bEnd {
                    segments.append((bEnd, shift.end))
                }
            }
            
            return total + segments.reduce(0) {
                $0 + viewModel.earningsForShift(from: $1.0, to: $1.1)
            }
        }
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
        
        if let index = editingShiftIndex {
            viewModel.shifts[index] = newShift
            editingShiftIndex = nil
        } else {
            viewModel.shifts.append(newShift)
        }
        
        resetForm()
    }
    
    func editShiftById(_ id: UUID) {
        guard let index = viewModel.shifts.firstIndex(where: { $0.id == id }) else { return }
        editShift(at: index)
    }
    
    func editShift(at index: Int) {
        let shift = viewModel.shifts[index]
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
        editingShiftIndex = index
    }
    
    func resetForm() {
        start = Date()
        end = Date()
        includeBreak = false
        breakPaid = false
        editingShiftIndex = nil
    }
    
    func deleteFilteredShifts(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredShifts[$0].id }
        viewModel.shifts.removeAll { idsToDelete.contains($0.id) }
    }
    
    func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
}

// MARK: - Formatting
private extension ShiftView {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
    
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    static func formatShiftDate(_ shift: Shift) -> String {
        let day = dateFormatter.string(from: shift.start)
        let startTime = timeFormatter.string(from: shift.start)
        let endTime = timeFormatter.string(from: shift.end)
        return "\(day) \(startTime) – \(endTime)"
    }
    
    static func formatBreak(_ shift: Shift) -> String? {
        guard let bStart = shift.breakStart,
              let bEnd = shift.breakEnd else { return nil }
        
        let bStartTime = timeFormatter.string(from: bStart)
        let bEndTime = timeFormatter.string(from: bEnd)
        
        return "Break: \(bStartTime) – \(bEndTime) \(shift.breakPaid ? "(Paid)" : "(Unpaid)")"
    }
}
