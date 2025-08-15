//
//  PaySettings.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation

struct PaySettings: Codable {
    var dayRate: Double    // 08–17
    var eveningRate: Double // 17–23
    var nightRate: Double   // 23–08
    var weekendBonus: Double
}
