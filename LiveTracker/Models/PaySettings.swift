//
//  PaySettings.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation

struct PaySettings: Identifiable, Codable {
    var id = UUID()
    var dayRate: Double    // 08–17
    var eveningRate: Double // 17–24
    var nightRate: Double   // 24–08
    var weekendBonus: Double
    var showEarned: Bool = true
    var startRange: Date
    var endRange: Date
    var HourlyPay: Double = 0.00
}
