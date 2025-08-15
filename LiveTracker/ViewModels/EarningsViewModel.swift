//
//  EarningsViewModel.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import Combine
import SwiftUI

class EarningsViewModel: ObservableObject {
    @Published var shifts: [Shift] = [] {
        didSet { saveShifts() }
    }
    @Published var currentEarnings: Double = 0.0
    @Published var currentlyHourly: Double = 0.0
    
    private var timer: AnyCancellable?
    private let settingsVM: SettingsViewModel
    
    init(settingsVM: SettingsViewModel) {
        self.settingsVM = settingsVM
        loadShifts()
        startTimer()
    }
    
    func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.updateEarnings()
            }
    }
    
    func deleteShifts(at offsets: IndexSet) {
        shifts.remove(atOffsets: offsets)
    }
    
    func isOnBreak() -> Bool {
        let now = Date()
        
        for shift in shifts {
            // Only check active shift
            if now >= shift.start && now <= shift.end {
                if let bStart = shift.breakStart,
                   let bEnd = shift.breakEnd,
                   now >= bStart && now <= bEnd {
                    return true
                }
            }
        }
        return false
    }

    
    func updateEarnings() {
        let now = Date()
        let calendar = Calendar.current
        var total: Double = 0
        
        for shift in shifts {
            // Only include shifts in the current month
            guard calendar.isDate(shift.start, equalTo: now, toGranularity: .month),
                  calendar.isDate(shift.start, equalTo: now, toGranularity: .year) else {
                continue
            }
            
            if now < shift.start { continue }
            
            let workedUntil = min(now, shift.end)
            var segments: [(Date, Date)] = [(shift.start, workedUntil)]
            
            // Handle unpaid breaks
            if let bStart = shift.breakStart, let bEnd = shift.breakEnd, !shift.breakPaid {
                segments = []
                if shift.start < bStart {
                    segments.append((shift.start, min(bStart, workedUntil)))
                }
                if workedUntil > bEnd {
                    segments.append((max(bEnd, shift.start), workedUntil))
                }
            }
            
            for (segStart, segEnd) in segments {
                total += earningsForShift(from: segStart, to: segEnd)
            }
        }
        
        currentEarnings = total
    }


    
    func earningsForShift(from start: Date, to end: Date) -> Double {
        var earnings: Double = 0
        var currentTime = start
        
        while currentTime < end {
            let rate = hourlyRate(for: currentTime)
            let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: currentTime)!
            let segmentEnd = min(end, nextHour)
            
            let seconds = segmentEnd.timeIntervalSince(currentTime)
            earnings += (seconds / 3600.0) * rate
            
            currentTime = segmentEnd
        }
        
        return earnings
    }
    
    func hourlyRate(for date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        var rate: Double
        
        if hour >= 8 && hour < 18 {
            rate = settingsVM.settings.dayRate
        } else if hour >= 18 && hour < 23 {
            rate = settingsVM.settings.eveningRate
        } else {
            rate = settingsVM.settings.nightRate
        }
        
        if weekday == 1 || weekday == 7 { // Sunday = 1, Saturday = 7
            rate = settingsVM.settings.weekendBonus
        }
        
        return rate
    }
    
    func secondsWorked(in shift: Shift, until now: Date) -> Int {
        let start = max(shift.start, Calendar.current.startOfMonth(for: now))
        let end = min(shift.end, now)
        return max(0, Int(end.timeIntervalSince(start)))
    }
    
    func saveShifts() {
        if let encoded = try? JSONEncoder().encode(shifts) {
            UserDefaults.standard.set(encoded, forKey: "Shifts")
        }
    }
    
    func loadShifts() {
        if let data = UserDefaults.standard.data(forKey: "Shifts"),
           let decoded = try? JSONDecoder().decode([Shift].self, from: data) {
            shifts = decoded
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        return self.date(from: self.dateComponents([.year, .month], from: date))!
    }
}
