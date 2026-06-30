//
//  SettingsViewModel.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//

import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var settings: [PaySettings] {
        didSet {
            revision &+= 1
            save()
            changeHandler?()
        }
    }
    
    var showEarned: Bool {
        didSet { defaults.set(showEarned, forKey: "ShowEarned") }
    }

    var persistenceError: String?
    var periodErrorMessage: String?
    private(set) var revision: UInt64 = 0

    private let defaults: UserDefaults
    @ObservationIgnored private var changeHandler: (() -> Void)?
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showEarned = defaults.object(forKey: "ShowEarned") as? Bool ?? true
        
        self.settings = [Self.makeDefault()]

        guard let data = defaults.data(forKey: "PaySettings") else { return }
        do {
            settings = try Self.decodeSettings(from: data)
            save()
        } catch {
            persistenceError = "Dina löneinställningar kunde inte läsas: \(error.localizedDescription)"
        }
    }
    
    func paySettings(for date: Date) -> PaySettings? {
        settings.first { $0.startRange <= date && date < $0.endRange }
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        changeHandler = handler
    }

    @discardableResult
    func createPayPeriod(referenceDate: Date = .now, calendar: Calendar = .current) -> UUID? {
        let latestStart = settings.map(\.startRange).max() ?? referenceDate
        let anchorDate = max(referenceDate, latestStart)
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: anchorDate),
              let proposedStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: nextMonth)
              ) else {
            periodErrorMessage = "Startdatum för den nya löneperioden kunde inte skapas."
            return nil
        }

        let start = calendar.startOfDay(for: proposedStart)
        var updated = settings.sorted { $0.startRange < $1.startRange }

        guard !updated.contains(where: { $0.startRange == start }) else {
            periodErrorMessage = "En löneperiod börjar redan på det datumet."
            return nil
        }

        guard let sourceIndex = updated.firstIndex(where: {
            $0.startRange < start && start < $0.endRange
        }) else {
            periodErrorMessage = "Den nya löneperioden måste börja inom en befintlig löneperiod."
            return nil
        }

        let source = updated[sourceIndex]
        updated[sourceIndex].endRange = start

        var newSetting = PaySettings(startRange: start, endRange: source.endRange)
        newSetting.hourlyRate = source.hourlyRate
        newSetting.recalculateRates()
        updated.insert(newSetting, at: sourceIndex + 1)
        settings = updated
        periodErrorMessage = nil
        return newSetting.id
    }

    func deletePayPeriod(id: UUID) {
        var updated = settings.sorted { $0.startRange < $1.startRange }
        guard updated.count > 1,
              let index = updated.firstIndex(where: { $0.id == id }) else { return }

        let deleted = updated[index]
        if index > 0 {
            updated[index - 1].endRange = deleted.endRange
        } else if updated.indices.contains(index + 1) {
            updated[index + 1].startRange = deleted.startRange
        }
        updated.remove(at: index)
        settings = updated
        periodErrorMessage = nil
    }

    func updateHourlyRate(for id: UUID, to hourlyRate: Decimal) {
        var updated = settings
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].hourlyRate = max(0, hourlyRate)
        updated[index].recalculateRates()
        settings = updated
    }

    func updateStartDate(for id: UUID, to date: Date, calendar: Calendar = .current) {
        var updated = settings.sorted { $0.startRange < $1.startRange }
        let start = calendar.startOfDay(for: date)
        guard let index = updated.firstIndex(where: { $0.id == id }),
              start < updated[index].endRange else {
            periodErrorMessage = "Startdatum måste vara före slutdatum."
            return
        }

        if index > 0 {
            guard start > updated[index - 1].startRange else {
                periodErrorMessage = "Startdatumet överlappar föregående löneperiod."
                return
            }
            updated[index - 1].endRange = start
        }
        updated[index].startRange = start
        settings = updated
        periodErrorMessage = nil
    }

    func updateEndDate(for id: UUID, to date: Date, calendar: Calendar = .current) {
        var updated = settings.sorted { $0.startRange < $1.startRange }
        let end = calendar.startOfDay(for: date)
        guard let index = updated.firstIndex(where: { $0.id == id }),
              updated[index].startRange < end else {
            periodErrorMessage = "Slutdatum måste vara efter startdatum."
            return
        }

        if updated.indices.contains(index + 1) {
            guard end < updated[index + 1].endRange else {
                periodErrorMessage = "Slutdatumet överlappar nästa löneperiod."
                return
            }
            updated[index + 1].startRange = end
        }
        updated[index].endRange = end
        settings = updated
        periodErrorMessage = nil
    }
    
    func save() {
        do {
            let encoded = try JSONEncoder().encode(settings)
            defaults.set(encoded, forKey: "PaySettings")
            persistenceError = nil
        } catch {
            persistenceError = "Dina löneinställningar kunde inte sparas: \(error.localizedDescription)"
        }
    }

    private static func decodeSettings(from data: Data) throws -> [PaySettings] {
        do {
            let settings = try normalized(JSONDecoder().decode([PaySettings].self, from: data))
            guard !settings.isEmpty else { throw SettingsDecodingError.emptySettings }
            return settings
        } catch let error as SettingsDecodingError {
            throw error
        } catch {
            var setting = try JSONDecoder().decode(PaySettings.self, from: data)
            setting.startRange = fallbackStart
            setting.endRange = fallbackEnd
            return try normalized([setting])
        }
    }

    private static func normalized(_ storedSettings: [PaySettings]) throws -> [PaySettings] {
        var result = storedSettings.sorted { $0.startRange < $1.startRange }

        for index in result.indices {
            guard result[index].startRange < result[index].endRange else {
                throw SettingsDecodingError.invalidRange
            }
            result[index].hourlyRate = max(0, result[index].hourlyRate)
            result[index].recalculateRates()
        }

        for index in result.indices.dropLast() {
            guard result[index].startRange < result[index + 1].startRange else {
                throw SettingsDecodingError.invalidRange
            }
            result[index].endRange = result[index + 1].startRange
        }
        return result
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

private enum SettingsDecodingError: LocalizedError {
    case emptySettings
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .emptySettings:
            "Inga löneinställningar fanns sparade."
        case .invalidRange:
            "De sparade löneperioderna innehåller ett ogiltigt datumintervall."
        }
    }
}
