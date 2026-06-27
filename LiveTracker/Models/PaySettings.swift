//
//  PaySettings.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation

struct PaySettings: Identifiable, Codable {
    var id = UUID()
    
    var hourlyRate: Double = 0
    
    var dayRate: Double = 0    // 08–17
    var eveningRate: Double = 0 // 17–24
    var nightRate: Double = 0   // 24–08
    var weekendRate: Double = 0
    var holidayRateA: Double = 0
    var holidayRateB: Double = 0
    
    var showEarned: Bool = true
    
    var startRange: Date
    var endRange: Date
    
    private static let vacationBonusRate: Double = 0.125
    private static let taxRate: Double = 0.3
    
    // MARK: - OB Constants
    private static let standardHoursPerMonth: Double = 160 // 8 * 5 * 4
    private static let eveningOBDivisor: Double = 600
    private static let nightOBDivisor: Double = 400
    private static let weekendOBDivisor: Double = 300
    private static let holidayAOBDivisor: Double = 300
    private static let holidayBOBDivisor: Double = 150
    
    mutating func recalculateRates() {
        guard hourlyRate > 0 else {
            dayRate = 0
            eveningRate = 0
            nightRate = 0
            weekendRate = 0
            holidayRateA = 0
            return
        }
        
        let monthlySalary = hourlyRate * Self.standardHoursPerMonth
        let eveningOB = monthlySalary / Self.eveningOBDivisor
        let nightOB = monthlySalary / Self.nightOBDivisor
        let weekendOB = monthlySalary / Self.weekendOBDivisor
        let holidayAOB = monthlySalary / Self.holidayAOBDivisor
        let holidayBOB = monthlySalary / Self.holidayBOBDivisor
        
        dayRate = Self.netForOneHour(grossRate: hourlyRate)
        eveningRate = Self.netForOneHour(grossRate: hourlyRate + eveningOB)
        nightRate = Self.netForOneHour(grossRate: hourlyRate + nightOB)
        weekendRate = Self.netForOneHour(grossRate: hourlyRate + weekendOB)
        holidayRateA = Self.netForOneHour(grossRate: hourlyRate + holidayAOB)
        holidayRateB = Self.netForOneHour(grossRate: hourlyRate + holidayBOB)
    
        
    }
    
    private static func netForOneHour(grossRate: Double) -> Double {
        let vacation = grossRate * vacationBonusRate
        let taxBase = floor(grossRate * taxRate)
        let taxVacation = floor(vacation * taxRate)
        return round(grossRate + vacation - taxBase - taxVacation)
    }

}
