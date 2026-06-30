import Foundation
import Observation

@Observable
@MainActor
final class TaxRefundViewModel {
    private let earningsViewModel: EarningsViewModel
    private let calculator: TaxRefundCalculator
    private let calendar: Calendar

    var selectedIncomeYear: Int
    private(set) var forecast: TaxRefundForecast?
    var errorMessage: String?

    init(
        earningsViewModel: EarningsViewModel,
        calculator: TaxRefundCalculator = TaxRefundCalculator(),
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.earningsViewModel = earningsViewModel
        self.calculator = calculator
        self.calendar = calendar
        let currentYear = calendar.component(.year, from: now)
        self.selectedIncomeYear = Self.supportedIncomeYears(currentYear: currentYear)
            .first { $0 <= currentYear - 1 }
            ?? Self.supportedIncomeYears(currentYear: currentYear).first
            ?? currentYear - 1
    }

    var availableIncomeYears: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        return Self.supportedIncomeYears(currentYear: currentYear)
    }

    func load() {
        do {
            forecast = try makeForecast(for: selectedIncomeYear)
            errorMessage = nil
        } catch {
            forecast = nil
            errorMessage = "Skatteuppskattningen kunde inte beräknas: \(error.localizedDescription)"
        }
    }

    private func makeForecast(for year: Int) throws -> TaxRefundForecast? {
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
            throw CocoaError(.coderInvalidValue)
        }

        let shifts = try earningsViewModel.shifts(from: yearStart, to: yearEnd)
        let provider: (Date) -> PaySettings? = { [weak earningsViewModel] date in
            earningsViewModel?.settingsVM.paySettings(for: date)
        }
        var monthlyEarnings: [Int: EarningsBreakdown] = [:]

        for shift in shifts {
            for segment in earningsViewModel.calculator.workSegments(for: shift, workedUntil: shift.end) {
                let clippedStart = max(segment.start, yearStart)
                let clippedEnd = min(segment.end, yearEnd)
                guard clippedStart < clippedEnd else { continue }

                let month = calendar.component(.month, from: clippedStart)
                let breakdown = earningsViewModel.calculator.breakdownForSegment(
                    from: clippedStart,
                    to: clippedEnd,
                    calendar: calendar,
                    paySettingsProvider: provider
                )
                monthlyEarnings[month, default: EarningsBreakdown()] += breakdown
            }
        }

        return calculator.forecast(incomeYear: year, monthlyEarnings: monthlyEarnings)
    }

    private static func supportedIncomeYears(currentYear: Int) -> [Int] {
        TaxRefundCalculator.supportedIncomeYears.filter { $0 <= currentYear }
    }
}
