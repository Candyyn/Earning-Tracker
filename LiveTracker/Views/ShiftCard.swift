//
//  ShiftCard.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-09-11.
//
import SwiftUI
import SwiftData

// MARK: - String Extension

extension String {
    func capitalizingFirstLetter() -> String {
        prefix(1).uppercased() + self.lowercased().dropFirst()
    }
}

// MARK: - Shared Formatters (allocated once)

private enum ShiftFormatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - ShiftCard View

struct ShiftCard: View, Equatable {
    let shift: Shift
    var viewModel: EarningsViewModel
    
    static func == (lhs: ShiftCard, rhs: ShiftCard) -> Bool {
        lhs.shift == rhs.shift
    }

    var body: some View {
        let shiftType = shift.dominantShiftType ?? .day

        HStack {
            Image(systemName: iconName(for: shiftType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundColor(iconColor(for: shiftType))
                .padding(.leading, 8)

            Divider()
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(topLine(for: shift))
                    .font(.system(.caption, weight: .medium))

                Text(bottomLine(for: shift))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(earningsString(for: shift))
                    .font(.headline)
                    .foregroundStyle(.green)
                    .privacySensitive()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText(for: shift, shiftType: shiftType))
    }

    // MARK: - Earnings

    private func earningsString(for shift: Shift) -> String {
        let value = earnings(for: shift)
        return ShiftFormatters.currency.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func earnings(for shift: Shift) -> Double {
        viewModel.earningsForFullShift(shift)
    }

    // MARK: - Display Strings

    private func topLine(for shift: Shift) -> String {
        "\(durationString(for: shift)) · \(timeRangeString(for: shift)) · \(dateRangeString(for: shift))"
    }

    private func bottomLine(for shift: Shift) -> String {
        let weekday = weekdayString(for: shift.start)
        let type = shift.dominantShiftType ?? .day
        return "\(weekday) · \(type.displayName) Shift"
    }

    private func durationString(for shift: Shift) -> String {
        let total = shift.end.timeIntervalSince(shift.start)
        let breakDuration: TimeInterval
        if let bStart = shift.breakStart, let bEnd = shift.breakEnd, !shift.breakPaid {
            breakDuration = bEnd.timeIntervalSince(bStart)
        } else {
            breakDuration = 0
        }
        let hours = Int((total - breakDuration) / 3600)
        return "\(hours)h"
    }

    private func timeRangeString(for shift: Shift) -> String {
        let f = ShiftFormatters.time
        return "\(f.string(from: shift.start))–\(f.string(from: shift.end))"
    }

    private func dateRangeString(for shift: Shift) -> String {
        let startDay   = ShiftFormatters.day.string(from: shift.start)
        let endDay     = ShiftFormatters.day.string(from: shift.end)
        let startMonth = ShiftFormatters.month.string(from: shift.start)
        let endMonth   = ShiftFormatters.month.string(from: shift.end)

        if startDay == endDay, startMonth == endMonth {
            return "\(startDay) \(startMonth)"
        } else if startMonth == endMonth {
            return "\(startDay)–\(endDay) \(startMonth)"
        } else {
            return "\(startDay) \(startMonth)–\(endDay) \(endMonth)"
        }
    }

    private func weekdayString(for date: Date) -> String {
        ShiftFormatters.weekday.string(from: date)
    }

    private func accessibilityLabelText(for shift: Shift, shiftType: ShiftType) -> String {
        let dateStr = ShiftFormatters.weekday.string(from: shift.start) + ", " + DateFormatter.localizedString(from: shift.start, dateStyle: .medium, timeStyle: .none)
        let startStr = ShiftFormatters.time.string(from: shift.start)
        let endStr = ShiftFormatters.time.string(from: shift.end)
        let earned = earningsString(for: shift)
        return "Shift on \(dateStr) from \(startStr) to \(endStr), \(shiftType.displayName) shift, earned \(earned)."
    }

    // MARK: - Icon Helpers

    func iconName(for type: ShiftType) -> String {
        switch type {
        case .day:     return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night:   return "moon.stars.fill"
        case .weekend: return "sparkles"
        case .holiday, .holidayMajor: return "star.fill"
        }
    }

    func iconColor(for type: ShiftType) -> Color {
        switch type {
        case .day:     return .yellow
        case .evening: return .orange
        case .night:   return .blue
        case .weekend, .holiday, .holidayMajor: return .purple
        }
    }
}
