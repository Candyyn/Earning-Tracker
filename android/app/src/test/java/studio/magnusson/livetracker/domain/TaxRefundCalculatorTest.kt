package studio.magnusson.livetracker.domain

import org.junit.Assert.*
import org.junit.Test

class TaxRefundCalculatorTest {
    private val calculator = TaxRefundCalculator()

    @Test fun populatedMonthsProduceOrderedRanges() {
        val monthly = (1..10).associateWith { EarningsBreakdown(20_000.0, 2_500.0, 6_750.0, 15_750.0) }
        val forecast = requireNotNull(calculator.forecast(2025, monthly))
        assertEquals(10, forecast.trackedMonthCount)
        assertEquals(ForecastConfidence.HIGH, forecast.confidence)
        assertTrue(forecast.estimatedFinalTax.start <= forecast.estimatedFinalTax.endInclusive)
        assertTrue(forecast.estimatedBalance.start <= forecast.estimatedBalance.endInclusive)
        assertEquals(157_500.0, forecast.earnings.netPay, .001)
    }

    @Test fun missingMonthsReduceConfidenceAndWidenUncertainty() {
        val month = EarningsBreakdown(100_000.0, 12_500.0, 33_750.0, 78_750.0)
        val sparse = requireNotNull(calculator.forecast(2025, mapOf(1 to month)))
        val complete = requireNotNull(calculator.forecast(2025, (1..12).associateWith { month }))
        val sparseWidth = (sparse.estimatedFinalTax.endInclusive - sparse.estimatedFinalTax.start) / sparse.earnings.taxableGross
        val completeWidth = (complete.estimatedFinalTax.endInclusive - complete.estimatedFinalTax.start) / complete.earnings.taxableGross
        assertEquals(ForecastConfidence.LOW, sparse.confidence)
        assertEquals(ForecastConfidence.HIGH, complete.confidence)
        assertTrue(sparseWidth > completeWidth)
    }

    @Test fun noTrackedEarningsProducesNoForecast() = assertNull(calculator.forecast(2025, emptyMap()))
}
