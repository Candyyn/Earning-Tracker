import SwiftData
import SwiftUI

struct ShiftView: View {
    var viewModel: EarningsViewModel

    @Query(sort: \Shift.start, order: .forward) private var allShifts: [Shift]
    @State private var editor: ShiftEditorViewModel
    @State private var pendingDeletion: Shift?

    init(viewModel: EarningsViewModel) {
        self.viewModel = viewModel
        _editor = State(initialValue: ShiftEditorViewModel(earningsViewModel: viewModel))
    }

    var body: some View {
        @Bindable var editor = editor

        List {
            Section {
                MonthNavigator(
                    selectedMonth: editor.selectedMonth,
                    onPrevious: { editor.changeMonth(by: -1) },
                    onNext: { editor.changeMonth(by: 1) }
                )
            }

            if filteredShifts.isEmpty {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(.largeTitle, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("Inga pass")
                            .font(.title2.bold())

                        Text("Lägg till ett pass för att börja följa månaden.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            editor.presentNewShift(referenceDate: editor.selectedMonth)
                        } label: {
                            Label("Lägg till pass", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.accentColor)
                        .controlSize(.regular)
                        .accessibilityIdentifier("shifts.empty.add")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowInsets(EdgeInsets())
                }
            } else {
                Section("Översikt") {
                    MonthlyShiftSummary(
                        shiftCount: filteredShifts.count,
                        hours: monthHours.total,
                        earnings: monthEarnings,
                        breakdown: monthBreakdown
                    )
                }

                ForEach(groupedShifts, id: \.day) { group in
                    Section {
                        ForEach(group.shifts) { shift in
                            ShiftRow(shift: shift, earnings: viewModel.earningsForFullShift(shift))
                                .accessibilityIdentifier("shifts.row")
                                .contentShape(Rectangle())
                                .onTapGesture { editor.edit(shift) }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button("Redigera", systemImage: "pencil") {
                                        editor.edit(shift)
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Ta bort", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = shift
                                    }
                                }
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    }
                }
            }
        }
        .accessibilityIdentifier("shifts.list")
        .navigationTitle("Arbetspass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CalendarSyncMenu(viewModel: viewModel, editor: editor)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editor.presentNewShift(referenceDate: editor.selectedMonth)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Lägg till pass")
                .accessibilityIdentifier("shifts.add")
            }
        }
        .sheet(isPresented: $editor.isEditorPresented) {
            ShiftEditorSheet(editor: editor, allShifts: allShifts)
                .presentationDetents([.large])
                .interactiveDismissDisabled(editor.isDirty)
        }
        .task {
            await editor.synchronizeCalendarIfEnabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await editor.synchronizeCalendarIfEnabled()
            }
        }
        .confirmationDialog(
            "Ta bort pass?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { shift in
            Button("Ta bort pass", role: .destructive) {
                editor.delete([shift])
                pendingDeletion = nil
            }
            Button("Avbryt", role: .cancel) {}
        } message: { _ in
            Text("Passet tas bort från LiveTracker och, när kalendern är ansluten, från Kalender.")
        }
        .alert("Passproblem", isPresented: Binding(
            get: { editor.errorMessage != nil },
            set: { if !$0 { editor.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }
}

private extension ShiftView {
    var filteredShifts: [Shift] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: editor.selectedMonth) else {
            return []
        }
        return allShifts.filter { interval.contains($0.start) }
    }

    var groupedShifts: [(day: Date, shifts: [Shift])] {
        Dictionary(grouping: filteredShifts) { Calendar.current.startOfDay(for: $0.start) }
            .map { (day: $0.key, shifts: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }

    var monthHours: HoursByShiftType {
        viewModel.workedHoursByType(for: filteredShifts)
    }

    var monthEarnings: Decimal {
        viewModel.totalEarningsForShifts(filteredShifts)
    }

    var monthBreakdown: [ShiftTypeBreakdown] {
        let shiftCounts = Dictionary(grouping: filteredShifts) {
            $0.dominantShiftType ?? .day
        }.mapValues { $0.count }
        let hoursByType = monthHours

        return ShiftType.allCases.compactMap { type in
            let hours = hoursByType.hours(for: type)
            let shiftCount = shiftCounts[type, default: 0]
            guard hours > 0 || shiftCount > 0 else { return nil }
            return ShiftTypeBreakdown(type: type, shiftCount: shiftCount, hours: hours)
        }
    }
}

private struct MonthNavigator: View {
    let selectedMonth: Date
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Föregående månad")
            .accessibilityIdentifier("shifts.previousMonth")
            .buttonStyle(.borderless)

            Spacer()

            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Nästa månad")
            .accessibilityIdentifier("shifts.nextMonth")
            .buttonStyle(.borderless)
        }
    }
}

private struct ShiftTypeBreakdown: Identifiable {
    let type: ShiftType
    let shiftCount: Int
    let hours: Double

    var id: ShiftType { type }
}

private struct MonthlyShiftSummary: View {
    let shiftCount: Int
    let hours: Double
    let earnings: Decimal
    let breakdown: [ShiftTypeBreakdown]

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    metric(title: "Pass", value: shiftCount.formatted(.number.locale(SwedishMarket.locale)))
                    Divider()
                    metric(title: "Timmar", value: formattedHours(hours))
                    Divider()
                    metric(title: "Intjänat", value: SwedishMarket.currencyWithOre(earnings))
                        .privacySensitive()
                }

                VStack(spacing: 10) {
                    LabeledContent("Pass", value: shiftCount.formatted(.number.locale(SwedishMarket.locale)))
                    LabeledContent("Timmar", value: formattedHours(hours))
                    LabeledContent("Intjänat", value: SwedishMarket.currencyWithOre(earnings))
                        .privacySensitive()
                }
            }
            .padding(.vertical, 4)

            if !breakdown.isEmpty {
                Divider()
                    .padding(.vertical, 10)

                VStack(spacing: 12) {
                    ForEach(breakdown) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.type.systemImage)
                                .foregroundStyle(item.type.tint)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.type.displayName)
                                Text(shiftCountText(item.shiftCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text(formattedHours(item.hours))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedHours(_ hours: Double) -> String {
        SwedishMarket.hours(hours)
    }

    private func shiftCountText(_ count: Int) -> String {
        switch count {
        case 0: "Del av blandade pass"
        case 1: "Huvudtyp för 1 pass"
        default: "Huvudtyp för \(count) pass"
        }
    }
}

private extension HoursByShiftType {
    func hours(for type: ShiftType) -> Double {
        switch type {
        case .day: day
        case .evening: evening
        case .night: night
        case .weekend: weekend
        case .holiday: holiday
        case .holidayMajor: holidayMajor
        }
    }
}

private struct ShiftRow: View {
    let shift: Shift
    let earnings: Decimal

    private var shiftType: ShiftType {
        shift.dominantShiftType ?? .day
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shiftType.systemImage)
                .foregroundStyle(shiftType.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(durationText)
                    Text("•")
                    Text(shiftType.displayName)
                    if shift.breakStart != nil {
                        Text("•")
                        Text(shift.breakPaid ? "Betald rast" : "Rast")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(SwedishMarket.currencyWithOre(earnings))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .privacySensitive()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Dubbeltryck för att redigera passet.")
    }

    private var timeRange: String {
        "\(shift.start.formatted(.dateTime.locale(SwedishMarket.locale).hour().minute())) - \(shift.end.formatted(.dateTime.locale(SwedishMarket.locale).hour().minute()))"
    }

    private var durationText: String {
        let unpaidBreak: TimeInterval = if let start = shift.breakStart, let end = shift.breakEnd, !shift.breakPaid {
            end.timeIntervalSince(start)
        } else {
            0.0
        }
        let hours = max(0, shift.end.timeIntervalSince(shift.start) - unpaidBreak) / 3600
        return SwedishMarket.hours(hours)
    }

    private var accessibilityText: String {
        "\(timeRange), \(durationText), \(shiftType.displayName), \(SwedishMarket.currencyWithOre(earnings))"
    }
}

private extension ShiftType {
    var systemImage: String {
        switch self {
        case .day: "sun.max"
        case .evening: "sunset"
        case .night: "moon.stars"
        case .weekend: "calendar"
        case .holiday: "flag"
        case .holidayMajor: "star"
        }
    }

    var tint: Color {
        switch self {
        case .day: .yellow
        case .evening: .orange
        case .night: .blue
        case .weekend: .teal
        case .holiday: .red
        case .holidayMajor: .purple
        }
    }
}
