package studio.magnusson.livetracker.domain

import kotlin.math.max
import kotlin.math.min

enum class ForecastConfidence { LOW, MEDIUM, HIGH }

data class TaxRefundForecast(
    val incomeYear: Int,
    val earnings: EarningsBreakdown,
    val trackedMonthCount: Int,
    val estimatedFinalTax: ClosedFloatingPointRange<Double>,
    val estimatedBalance: ClosedFloatingPointRange<Double>,
) {
    val midpointBalance get() = (estimatedBalance.start + estimatedBalance.endInclusive) / 2.0
    val confidence get() = when (trackedMonthCount) {
        in 10..12 -> ForecastConfidence.HIGH
        in 6..9 -> ForecastConfidence.MEDIUM
        else -> ForecastConfidence.LOW
    }
}

class TaxRefundCalculator {
    fun forecast(incomeYear: Int, monthlyEarnings: Map<Int, EarningsBreakdown>): TaxRefundForecast? {
        val populated = monthlyEarnings.filterValues { it.taxableGross > 0.0 }
        if (populated.isEmpty()) return null
        val earnings = populated.values.fold(EarningsBreakdown(), EarningsBreakdown::plus)
        val rate = effectiveTaxRate(earnings.taxableGross, incomeYear)
        val missingMonths = max(0, 12 - populated.size)
        val uncertainty = min(0.10, 0.035 + missingMonths * 0.004)
        val finalTax = (earnings.taxableGross * max(0.0, rate - uncertainty))..(earnings.taxableGross * min(0.50, rate + uncertainty))
        return TaxRefundForecast(
            incomeYear,
            earnings,
            populated.size,
            finalTax,
            (earnings.estimatedWithheldTax - finalTax.endInclusive)..(earnings.estimatedWithheldTax - finalTax.start),
        )
    }

    private fun effectiveTaxRate(annualIncome: Double, incomeYear: Int): Double {
        val threshold = if (incomeYear >= 2026) 643_000.0 else 625_800.0
        return when {
            annualIncome <= 25_000 -> 0.02
            annualIncome <= 100_000 -> interpolate(annualIncome, 25_000.0..100_000.0, 0.02..0.12)
            annualIncome <= 250_000 -> interpolate(annualIncome, 100_000.0..250_000.0, 0.12..0.20)
            annualIncome <= threshold -> interpolate(annualIncome, 250_000.0..threshold, 0.20..0.25)
            else -> min(0.45, (threshold * 0.25 + (annualIncome - threshold) * 0.45) / annualIncome)
        }
    }

    private fun interpolate(value: Double, input: ClosedFloatingPointRange<Double>, rates: ClosedFloatingPointRange<Double>): Double {
        val progress = (value - input.start) / (input.endInclusive - input.start)
        return rates.start + progress * (rates.endInclusive - rates.start)
    }
}
