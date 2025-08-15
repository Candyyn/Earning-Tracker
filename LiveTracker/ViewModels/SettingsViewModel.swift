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
    @Published var settings: PaySettings {
        didSet { save() }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "PaySettings"),
           let decoded = try? JSONDecoder().decode(PaySettings.self, from: data) {
            settings = decoded
        } else {
            settings = PaySettings(dayRate: 0, eveningRate: 0, nightRate: 0, weekendBonus: 0)
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "PaySettings")
        }
    }
}
