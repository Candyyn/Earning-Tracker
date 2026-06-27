//
//  SettingsViewModel.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import SwiftUI
import Observation

@Observable
class SettingsViewModel {
    var settings: [PaySettings] {
        didSet { save() }
    }
    
    var showEarned: Bool {
        didSet { UserDefaults.standard.set(showEarned, forKey: "ShowEarned") }
    }
    
    init() {
        self.showEarned = UserDefaults.standard.object(forKey: "ShowEarned") as? Bool ?? true
        
        if let data = UserDefaults.standard.data(forKey: "PaySettings") {
            if let decoded = try? JSONDecoder().decode([PaySettings].self, from: data), !decoded.isEmpty {
                self.settings = decoded
            } else if var single = try? JSONDecoder().decode(PaySettings.self, from: data) {
                single.startRange = Self.fallbackStart
                single.endRange = Self.fallbackEnd
                self.settings = [single]
                save()
            } else {
                self.settings = [Self.makeDefault()]
            }
        } else {
            self.settings = [Self.makeDefault()]
        }
    }
    
    func paySettings(for date: Date) -> PaySettings? {
        return settings.first { $0.startRange <= date && date <= $0.endRange }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "PaySettings")
        }
    }
    
    
    private static var fallbackStart: Date {
        Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date.distantPast
    }
    private static var fallbackEnd: Date {
        Calendar.current.date(from: DateComponents(year: 2100, month: 1, day: 1)) ?? Date.distantFuture
    }
    
    static func makeDefault() -> PaySettings {
        PaySettings(startRange: fallbackStart, endRange: fallbackEnd)
    }
}
