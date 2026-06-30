import Foundation

struct TaxRefundForecast: Equatable, Sendable {
    enum Confidence: String, Sendable {
        case low = "Låg säkerhet"
        case medium = "Medelhög säkerhet"
        case high = "Högre säkerhet"
    }

    let incomeYear: Int
    let earnings: EarningsBreakdown
    let trackedMonthCount: Int
    let estimatedFinalTax: ClosedRange<Decimal>
    let estimatedBalance: ClosedRange<Decimal>

    var midpointBalance: Decimal {
        (estimatedBalance.lowerBound + estimatedBalance.upperBound) / 2
    }

    var confidence: Confidence {
        switch trackedMonthCount {
        case 10...12: .high
        case 6...9: .medium
        default: .low
        }
    }
}

struct TaxRefundCalculator: Sendable {
    static let supportedIncomeYears = [2026, 2025]

    private let localTaxRateRange: ClosedRange<Decimal> = 0.32...0.36

    func forecast(
        incomeYear: Int,
        monthlyEarnings: [Int: EarningsBreakdown]
    ) -> TaxRefundForecast? {
        let populatedMonths = monthlyEarnings.filter { $0.value.taxableGross > 0 }
        guard !populatedMonths.isEmpty else { return nil }

        let earnings = populatedMonths.values.reduce(into: EarningsBreakdown()) { $0 += $1 }
        let lowerTax = estimatedAnnualTax(
            for: earnings.taxableGross,
            incomeYear: incomeYear,
            combinedLocalTaxRate: localTaxRateRange.lowerBound
        )
        let upperTax = estimatedAnnualTax(
            for: earnings.taxableGross,
            incomeYear: incomeYear,
            combinedLocalTaxRate: localTaxRateRange.upperBound
        )
        let finalTax = min(lowerTax, upperTax)...max(lowerTax, upperTax)

        return TaxRefundForecast(
            incomeYear: incomeYear,
            earnings: earnings,
            trackedMonthCount: populatedMonths.count,
            estimatedFinalTax: finalTax,
            estimatedBalance: (earnings.estimatedWithheldTax - finalTax.upperBound)...(earnings.estimatedWithheldTax - finalTax.lowerBound)
        )
    }

    func estimatedAnnualTax(
        for grossEmploymentIncome: Decimal,
        incomeYear: Int,
        combinedLocalTaxRate: Decimal = 0.34
    ) -> Decimal {
        let rules = SwedishIncomeTaxRules.rules(for: incomeYear)
        let annualIncome = max(0, grossEmploymentIncome).roundedDownToHundred()
        guard annualIncome > 0 else { return 0 }

        let generalDeduction = rules.generalDeduction(for: annualIncome)
        let taxableEarnedIncome = max(0, annualIncome - generalDeduction).roundedDownToHundred()
        guard taxableEarnedIncome > 0 else {
            return rules.generalPensionFee(for: annualIncome)
        }

        let burialAndFaithRate = rules.burialAndFaithFeeRate
        let municipalTaxRate = max(0, combinedLocalTaxRate - burialAndFaithRate)
        let municipalTax = (taxableEarnedIncome * municipalTaxRate).roundedDownToWholeKrona()
        let burialAndFaithFee = (taxableEarnedIncome * burialAndFaithRate).roundedDownToWholeKrona()
        let stateTax = rules.stateIncomeTax(for: taxableEarnedIncome)
        let pensionFee = rules.generalPensionFee(for: annualIncome)
        let publicServiceFee = rules.publicServiceFee(for: taxableEarnedIncome)

        let pensionReduction = min(pensionFee, stateTax + municipalTax)
        let municipalTaxAfterPensionReduction = max(0, municipalTax - pensionReduction)
        let workReduction = min(
            rules.workIncomeTaxReduction(
                for: annualIncome,
                generalDeduction: generalDeduction,
                municipalTaxRate: municipalTaxRate
            ),
            municipalTaxAfterPensionReduction
        )
        let municipalTaxAfterWorkReduction = max(0, municipalTaxAfterPensionReduction - workReduction)
        let earnedIncomeReduction = min(
            rules.earnedIncomeTaxReduction(for: taxableEarnedIncome),
            municipalTaxAfterWorkReduction
        )

        let taxBeforeReductions = stateTax + municipalTax + burialAndFaithFee + pensionFee + publicServiceFee
        let reductions = pensionReduction + workReduction + earnedIncomeReduction
        return max(0, taxBeforeReductions - reductions).roundedDownToWholeKrona()
    }
}

private struct SwedishIncomeTaxRules: Sendable {
    let priceBaseAmount: Decimal
    let incomeBaseAmount: Decimal
    let stateTaxThreshold: Decimal
    let workReductionUpperSlope: Decimal
    let workReductionCapMultiplier: Decimal
    let publicServiceFeeCapMultiplier: Decimal

    let burialAndFaithFeeRate: Decimal = 0.0116

    static func rules(for incomeYear: Int) -> Self {
        if incomeYear >= 2026 {
            return Self(
                priceBaseAmount: 59_200,
                incomeBaseAmount: 83_400,
                stateTaxThreshold: 643_000,
                workReductionUpperSlope: 0.251,
                workReductionCapMultiplier: 3.027,
                publicServiceFeeCapMultiplier: 1.42
            )
        }

        return Self(
            priceBaseAmount: 58_800,
            incomeBaseAmount: 80_600,
            stateTaxThreshold: 625_800,
            workReductionUpperSlope: 0.199,
            workReductionCapMultiplier: 2.776,
            publicServiceFeeCapMultiplier: 1.55
        )
    }

    func generalDeduction(for annualIncome: Decimal) -> Decimal {
        let rawDeduction: Decimal
        if annualIncome <= priceBaseAmount * 0.99 {
            rawDeduction = priceBaseAmount * 0.423
        } else if annualIncome <= priceBaseAmount * 2.72 {
            rawDeduction = priceBaseAmount * 0.423 + (annualIncome - priceBaseAmount * 0.99) * 0.20
        } else if annualIncome <= priceBaseAmount * 3.11 {
            rawDeduction = priceBaseAmount * 0.77
        } else if annualIncome <= priceBaseAmount * 7.88 {
            rawDeduction = priceBaseAmount * 0.77 - (annualIncome - priceBaseAmount * 3.11) * 0.10
        } else {
            rawDeduction = priceBaseAmount * 0.293
        }

        return min(annualIncome, rawDeduction.roundedUpToHundred())
    }

    func stateIncomeTax(for taxableEarnedIncome: Decimal) -> Decimal {
        guard taxableEarnedIncome > stateTaxThreshold else { return 0 }
        return ((taxableEarnedIncome - stateTaxThreshold) * 0.20).roundedDownToWholeKrona()
    }

    func generalPensionFee(for annualIncome: Decimal) -> Decimal {
        guard annualIncome >= priceBaseAmount * 0.423 else { return 0 }

        let cappedIncome = min(annualIncome, incomeBaseAmount * 8.07)
        return (cappedIncome * 0.07).roundedToNearestHundredHalfDown()
    }

    func workIncomeTaxReduction(
        for annualIncome: Decimal,
        generalDeduction: Decimal,
        municipalTaxRate: Decimal
    ) -> Decimal {
        let workIncome = annualIncome.roundedDownToHundred()
        let reductionBase: Decimal
        if workIncome <= priceBaseAmount * 0.91 {
            reductionBase = workIncome - generalDeduction
        } else if workIncome <= priceBaseAmount * 3.24 {
            reductionBase = priceBaseAmount * 0.91
                + (workIncome - priceBaseAmount * 0.91) * 0.3874
                - generalDeduction
        } else if workIncome <= priceBaseAmount * 8.08 {
            reductionBase = priceBaseAmount * 1.813
                + (workIncome - priceBaseAmount * 3.24) * workReductionUpperSlope
                - generalDeduction
        } else {
            reductionBase = priceBaseAmount * workReductionCapMultiplier - generalDeduction
        }

        return max(0, reductionBase * municipalTaxRate).roundedDownToWholeKrona()
    }

    func earnedIncomeTaxReduction(for taxableEarnedIncome: Decimal) -> Decimal {
        if taxableEarnedIncome <= 40_000 {
            return 0
        } else if taxableEarnedIncome <= 240_000 {
            return ((taxableEarnedIncome - 40_000) * 0.0075).roundedDownToWholeKrona()
        } else {
            return 1_500
        }
    }

    func publicServiceFee(for taxableEarnedIncome: Decimal) -> Decimal {
        min(taxableEarnedIncome * 0.01, incomeBaseAmount * publicServiceFeeCapMultiplier * 0.01)
            .roundedDownToWholeKrona()
    }
}

private extension Decimal {
    func roundedUpToHundred() -> Decimal {
        (self / 100).rounded(scale: 0, mode: .up) * 100
    }

    func roundedDownToHundred() -> Decimal {
        (self / 100).rounded(scale: 0, mode: .down) * 100
    }

    func roundedDownToWholeKrona() -> Decimal {
        rounded(scale: 0, mode: .down)
    }

    func roundedToNearestHundredHalfDown() -> Decimal {
        let lower = roundedDownToHundred()
        let remainder = self - lower
        return remainder > 50 ? lower + 100 : lower
    }

    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
