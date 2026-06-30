import Foundation
import Testing
@testable import LiveTracker

@MainActor
struct TaxRefundTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func earningsBreakdownReconcilesWithExistingNetEarnings() throws {
        var settings = PaySettings(
            hourlyRate: 180,
            startRange: .distantPast,
            endRange: .distantFuture
        )
        settings.recalculateRates()
        let calculator = EarningsCalculator(holidayService: MockHolidayService())
        let start = try #require(calendar.date(from: DateComponents(
            year: 2025, month: 6, day: 16, hour: 9
        )))
        let end = try #require(calendar.date(byAdding: .hour, value: 8, to: start))
        let shift = Shift(start: start, end: end)
        let provider: (Date) -> PaySettings? = { _ in settings }

        let existingNet = calculator.earningsForFullShift(
            shift,
            calendar: calendar,
            paySettingsProvider: provider
        )
        let breakdown = calculator.breakdownForFullShift(
            shift,
            calendar: calendar,
            paySettingsProvider: provider
        )

        #expect(breakdown.netPay == existingNet)
        #expect(breakdown.taxableGross - breakdown.estimatedWithheldTax == breakdown.netPay)
        #expect(breakdown.vacationPay == breakdown.grossPay * PaySettings.vacationBonusRate)
    }

    @Test func forecastUsesOnlyPopulatedMonthsAndProducesOrderedRanges() throws {
        let monthly: [Int: EarningsBreakdown] = Dictionary(uniqueKeysWithValues: (1...10).map { month in
            (month, EarningsBreakdown(
                grossPay: 20_000,
                vacationPay: 2_500,
                estimatedWithheldTax: 6_750,
                netPay: 15_750
            ))
        })

        let forecast = try #require(TaxRefundCalculator().forecast(
            incomeYear: 2025,
            monthlyEarnings: monthly
        ))

        #expect(forecast.trackedMonthCount == 10)
        #expect(forecast.confidence == .high)
        #expect(forecast.estimatedFinalTax.lowerBound <= forecast.estimatedFinalTax.upperBound)
        #expect(forecast.estimatedBalance.lowerBound <= forecast.estimatedBalance.upperBound)
        #expect(forecast.earnings.netPay == 157_500)
    }

    @Test func annualTaxMatchesSkatteverket2026CalculationExamples() {
        let calculator = TaxRefundCalculator()

        #expect(calculator.estimatedAnnualTax(
            for: 28_000,
            incomeYear: 2026,
            combinedLocalTaxRate: 0.34
        ) == 2_062)
        #expect(calculator.estimatedAnnualTax(
            for: 55_000,
            incomeYear: 2026,
            combinedLocalTaxRate: 0.34
        ) == 4_445)
    }

    @Test func localTaxRateRangeProducesOrderedTaxAndBalanceRanges() throws {
        let month = EarningsBreakdown(
            grossPay: 100_000,
            vacationPay: 12_500,
            estimatedWithheldTax: 33_750,
            netPay: 78_750
        )
        let sparse = try #require(TaxRefundCalculator().forecast(
            incomeYear: 2025,
            monthlyEarnings: [1: month]
        ))
        let complete = try #require(TaxRefundCalculator().forecast(
            incomeYear: 2025,
            monthlyEarnings: Dictionary(uniqueKeysWithValues: (1...12).map { ($0, month) })
        ))

        #expect(sparse.confidence == .low)
        #expect(complete.confidence == .high)
        #expect(sparse.estimatedFinalTax.lowerBound < sparse.estimatedFinalTax.upperBound)
        #expect(complete.estimatedBalance.lowerBound <= complete.estimatedBalance.upperBound)
    }

    @Test func noTrackedEarningsProducesNoForecast() {
        #expect(TaxRefundCalculator().forecast(incomeYear: 2025, monthlyEarnings: [:]) == nil)
    }

    @Test func fractionalHoursKeepDecimalPrecisionUntilPresentation() throws {
        var settings = PaySettings(
            hourlyRate: 100,
            startRange: .distantPast,
            endRange: .distantFuture
        )
        settings.recalculateRates()
        let calculator = EarningsCalculator(holidayService: MockHolidayService())
        let start = try #require(calendar.date(from: DateComponents(
            year: 2025, month: 6, day: 16, hour: 9
        )))
        let end = try #require(calendar.date(byAdding: .minute, value: 15, to: start))
        let shift = Shift(start: start, end: end)

        let earnings = calculator.earningsForFullShift(
            shift,
            calendar: calendar,
            paySettingsProvider: { _ in settings }
        )

        #expect(settings.dayRate == Decimal(string: "78.75"))
        #expect(earnings == Decimal(string: "19.6875"))
    }
}
