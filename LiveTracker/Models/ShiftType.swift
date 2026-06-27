//
//  ShiftType.swift
//  LiveTracker
//
//  Created by Emil Magnusson on 2026-06-25.
//

import Foundation

public enum ShiftType: String, Codable, CaseIterable {
    case day = "day"
    case evening = "evening"
    case night = "night"
    case weekend = "weekend"
    case holiday = "holiday"
    case holidayMajor = "holiday (major)"
    
    public var displayName: String {
        switch self {
        case .holidayMajor: return "Holiday (Major)"
        default: return rawValue.capitalized
        }
    }
}
