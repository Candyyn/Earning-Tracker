//
//  ShiftCard.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2025-09-11.
//
import SwiftUI

extension String {
    func capitalizingFirstLetter() -> String {
      return prefix(1).uppercased() + self.lowercased().dropFirst()
    }

    mutating func capitalizeFirstLetter() {
      self = self.capitalizingFirstLetter()
    }
}



struct ShiftCard: View {
    let shift: Shift
    @ObservedObject var viewModel: EarningsViewModel
    

    var body: some View {
        let shiftType = dominantType(for: shift)
        HStack {
            Image(systemName: iconName(for: shiftType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32) // icon size
                .foregroundColor(iconColor(for: shiftType))
                .padding(.leading, 8)
            
            Divider()
                .padding(.horizontal, 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(topLine(for: shift)) // format from `shift`
                    .font(.system(.caption, weight: .medium))

                Text(bottomLine(for: shift)) // also from `shift`
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(earningsString(for: shift))
                        .font(.headline)
                        .foregroundStyle(.green)
            }
            
            
             // pushes VStack and icon apart
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    
    // MARK: - Helpers
    
    private func earningsString(for shift: Shift) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        
        let value = earnings(for: shift)
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func earnings(for shift: Shift) -> Double {
    
        if shift.breakPaid ||
            shift.breakStart == nil ||
            shift.breakEnd == nil {
            
            return viewModel.earningsForShift(
                from: shift.start,
                to: shift.end
            )
        }
        
        guard let breakStart = shift.breakStart,
              let breakEnd = shift.breakEnd else {
            return viewModel.earningsForShift(
                from: shift.start,
                to: shift.end
            )
        }
        
        // 1️⃣ Earnings before break
        let beforeBreak = viewModel.earningsForShift(
            from: shift.start,
            to: breakStart
        )
        
        // 2️⃣ Earnings after break
        let afterBreak = viewModel.earningsForShift(
            from: breakEnd,
            to: shift.end
        )
        
        return beforeBreak + afterBreak
    }
    

    private func topLine(for shift: Shift) -> String {
        let duration = durationString(for: shift)
        let timeRange = timeRangeString(for: shift)
        let dateRange = dateRangeString(for: shift)
        return "\(duration) · \(timeRange) · \(dateRange)"
    }

    private func bottomLine(for shift: Shift) -> String {
        let weekday = weekdayString(for: shift.start)
        let shiftType = dominantType(for: shift)
        let capi = shiftType.capitalizingFirstLetter();
        return "\(weekday) · \(capi) Shift"
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: shift.start))–\(formatter.string(from: shift.end))"
    }

    private func dateRangeString(for shift: Shift) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        let startDay = dayFormatter.string(from: shift.start)
        let endDay = dayFormatter.string(from: shift.end)
        let startMonth = monthFormatter.string(from: shift.start)
        let endMonth = monthFormatter.string(from: shift.end)

        if startDay == endDay && startMonth == endMonth {
            // Same day + same month → just show one
            return "\(startDay) \(startMonth)"
        } else if startMonth == endMonth {
            // Same month → "11–12 Sep"
            return "\(startDay)–\(endDay) \(startMonth)"
        } else {
            // Different months → "30 Sep–1 Oct"
            return "\(startDay) \(startMonth)–\(endDay) \(endMonth)"
        }
    }


    private func weekdayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    
    func dominantType(for shift: Shift) -> String {
        let calendar = Calendar.current
        
        // Break shift into 15-min slices and count categories
        let step: TimeInterval = 15 * 60
        var counts: [String: TimeInterval] = ["day": 0, "evening": 0, "night": 0, "weekend": 0]
        
        var current = shift.start
        while current < shift.end {
            let next = current.addingTimeInterval(step)
            let sliceEnd = min(next, shift.end)
            let duration = sliceEnd.timeIntervalSince(current)
            
            let type = currentType(for: current, calendar: calendar) // reuse your earlier function
            counts[type, default: 0] += duration
            
            current = next
        }
        
        // Weekend rule: if all time is weekend, return weekend
        if counts["weekend", default: 0] > 0 && (counts["day", default: 0] + counts["evening", default: 0] + counts["night", default: 0] == 0) {
            return "weekend"
        }
        
        // Otherwise pick the largest bucket
        return counts.max(by: { $0.value < $1.value })?.key ?? "day"
    }

    private func currentType(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        
        if weekday == 1 || weekday == 7 {
            return "weekend"
        }
        switch hour {
        case 8..<18: return "day"
        case 18..<24: return "evening"
        default: return "night"
        }
    }
    
    func iconName(for type: String) -> String {
            switch type.lowercased() {
            case "day":
                return "sun.max.fill"
            case "evening":
                return "sunset.fill"
            case "night":
                return "moon.stars.fill"
            case "weekend":
                return "sparkles"
            default:
                return "questionmark.circle.fill"
            }
        }

        func iconColor(for type: String) -> Color {
            switch type.lowercased() {
            case "day":
                return .yellow
            case "evening":
                return .orange
            case "night":
                return .blue
            case "weekend":
                return .purple
            default:
                return .gray
            }
        }

}

    
