//
//  Shift.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation

struct Shift: Identifiable, Codable {
    var id = UUID()
    var start: Date
    var end: Date
    var breakStart: Date?
    var breakEnd: Date?
    var breakPaid: Bool = false
}
