//
//  SettingsViewModel.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @Published var settings: [PaySettings] {
        didSet { save() }
    }
    
    public func getByMonth(date: Date) -> PaySettings? {
        return settings.first { $0.startRange <= date && date <= $0.endRange }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "PaySettings") {
            if let decodedArray = try? JSONDecoder().decode([PaySettings].self, from: data) {
                settings = decodedArray
            } else if var decodedSingle = try? JSONDecoder().decode(PaySettings.self, from: data) {
                decodedSingle.startRange = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!
                decodedSingle.endRange = Calendar.current.date(from: DateComponents(year: 2100, month: 1, day: 1))!
                settings = [decodedSingle]
                save() // Optionally, update storage to new format
            } else {
                settings = [PaySettings(dayRate: 0, eveningRate: 0, nightRate: 0, weekendBonus: 0, showEarned: true, startRange: Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!, endRange: Calendar.current.date(from: DateComponents(year: 2100, month: 1, day: 1))!)]
            }
        } else {
            settings = [PaySettings(dayRate: 0, eveningRate: 0, nightRate: 0, weekendBonus: 0, showEarned: true, startRange: Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!, endRange: Calendar.current.date(from: DateComponents(year: 2100, month: 1, day: 1))!)]
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "PaySettings")
        }
    }
}

extension SettingsViewModel {
    static var preview: SettingsViewModel {
        let sm = SettingsViewModel()
        sm.settings = [PaySettings(dayRate: 0, eveningRate: 0, nightRate: 0, weekendBonus: 0, showEarned: true, startRange: Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!, endRange: Calendar.current.date(from: DateComponents(year: 2100, month: 1, day: 1))!)]
        // Add other mock setup if needed
        return sm
    }
}
