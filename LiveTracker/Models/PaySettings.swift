//
//  PaySettings.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation

struct PayRateBreakdown: Equatable, Sendable {
    let grossPay: Decimal
    let vacationPay: Decimal
    let estimatedWithheldTax: Decimal
    let netPay: Decimal

    var taxableGross: Decimal { grossPay + vacationPay }
}

struct PaySettings: Identifiable, Codable {
    var id = UUID()
    
    var hourlyRate: Decimal = 0
    
    var dayRate: Decimal = 0     // 08:00-18:00
    var eveningRate: Decimal = 0 // 18:00-24:00
    var nightRate: Decimal = 0   // 00:00-08:00
    var weekendRate: Decimal = 0
    var holidayRateA: Decimal = 0
    var holidayRateB: Decimal = 0
    
    var startRange: Date
    var endRange: Date
    
    static let vacationBonusRate: Decimal = 0.125
    static let taxRate: Decimal = 0.3
    
    // MARK: - OB Constants
    private static let standardHoursPerMonth: Decimal = 160 // 8 * 5 * 4
    private static let eveningOBDivisor: Decimal = 600
    private static let nightOBDivisor: Decimal = 400
    private static let weekendOBDivisor: Decimal = 300
    private static let holidayAOBDivisor: Decimal = 300
    private static let holidayBOBDivisor: Decimal = 150
    
    mutating func recalculateRates() {
        guard hourlyRate > 0 else {
            dayRate = 0
            eveningRate = 0
            nightRate = 0
            weekendRate = 0
            holidayRateA = 0
            holidayRateB = 0
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

    func rateBreakdown(for type: ShiftType) -> PayRateBreakdown {
        let grossRate = grossRate(for: type)
        let vacationPay = grossRate * Self.vacationBonusRate
        let netPay = netRate(for: type)

        return PayRateBreakdown(
            grossPay: grossRate,
            vacationPay: vacationPay,
            estimatedWithheldTax: max(0, grossRate + vacationPay - netPay),
            netPay: netPay
        )
    }

    private func grossRate(for type: ShiftType) -> Decimal {
        let monthlySalary = hourlyRate * Self.standardHoursPerMonth
        return switch type {
        case .day:
            hourlyRate
        case .evening:
            hourlyRate + monthlySalary / Self.eveningOBDivisor
        case .night:
            hourlyRate + monthlySalary / Self.nightOBDivisor
        case .weekend:
            hourlyRate + monthlySalary / Self.weekendOBDivisor
        case .holiday:
            hourlyRate + monthlySalary / Self.holidayAOBDivisor
        case .holidayMajor:
            hourlyRate + monthlySalary / Self.holidayBOBDivisor
        }
        
    }

    private func netRate(for type: ShiftType) -> Decimal {
        switch type {
        case .day: dayRate
        case .evening: eveningRate
        case .night: nightRate
        case .weekend: weekendRate
        case .holiday: holidayRateA
        case .holidayMajor: holidayRateB
        }
    }
    
    private static func netForOneHour(grossRate: Decimal) -> Decimal {
        let vacation = grossRate * vacationBonusRate
        return grossRate + vacation - ((grossRate + vacation) * taxRate)
    }
}
