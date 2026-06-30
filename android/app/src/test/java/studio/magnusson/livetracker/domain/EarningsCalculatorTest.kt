package studio.magnusson.livetracker.domain
import org.junit.Assert.assertEquals
import org.junit.Test
import studio.magnusson.livetracker.data.*
import java.time.*
class EarningsCalculatorTest {
    private val zone = ZoneId.of("Europe/Stockholm")
    private val calculator = EarningsCalculator(zone)
    private val settings = listOf(period(100.0, "2020-01-01T00:00", "2030-01-01T00:00"))
    @Test fun weekdayDayShift() = assertEquals(708.75, calculator.earnings(shift("2026-06-15T08:00", "2026-06-15T17:00"), settings), .01)
    @Test fun unpaidBreakIsExcluded() {
        val shift = shift("2026-06-15T08:00", "2026-06-15T17:00").copy(breakStartEpochMillis = instant("2026-06-15T12:00").toEpochMilli(), breakEndEpochMillis = instant("2026-06-15T13:00").toEpochMilli())
        assertEquals(630.0, calculator.earnings(shift, settings), .01)
    }
    @Test fun easterDate() = assertEquals(LocalDate.of(2026, 4, 5), HolidayCalendar.easterSunday(2026))
    @Test fun ratesMatchSwiftPrecisionAndZeroClearsAllRates() {
        val paid = period(100.0, "2020-01-01T00:00", "2030-01-01T00:00")
        assertEquals(78.75, paid.rate(ShiftType.DAY), .000001)
        assertEquals(99.75, paid.rate(ShiftType.EVENING), .000001)
        assertEquals(110.25, paid.rate(ShiftType.NIGHT), .000001)
        assertEquals(120.75, paid.rate(ShiftType.WEEKEND), .000001)
        assertEquals(0.0, paid.copy(grossHourlyRate = 0.0).rate(ShiftType.HOLIDAY_MAJOR), 0.0)
    }
    @Test fun shiftIsSplitAtPayPeriodBoundary() {
        val periods = listOf(
            period(100.0, "2026-06-01T00:00", "2026-06-15T12:00"),
            period(200.0, "2026-06-15T12:00", "2026-07-01T00:00"),
        )
        assertEquals(236.25, calculator.earnings(shift("2026-06-15T11:00", "2026-06-15T13:00"), periods), .001)
    }
    @Test fun partialMinutesAreNotSampled() {
        assertEquals(0.984375, calculator.earnings(shift("2026-06-15T08:00", "2026-06-15T08:00:45"), settings), .0001)
    }
    @Test fun dominantTypeUsesExactDurations() {
        assertEquals(ShiftType.DAY, calculator.dominantType(shift("2026-06-15T07:59:30", "2026-06-15T08:01:00")))
        assertEquals(ShiftType.NIGHT, calculator.dominantType(shift("2026-06-15T07:58:00", "2026-06-15T08:01:00")))
    }
    @Test fun anyHolidayTimeTakesDominantPrecedence() {
        assertEquals(ShiftType.HOLIDAY, calculator.dominantType(shift("2026-01-06T06:00", "2026-01-06T08:00")))
        assertEquals(ShiftType.HOLIDAY_MAJOR, calculator.dominantType(shift("2026-12-24T06:00", "2026-12-24T08:00")))
    }
    @Test fun workedDurationHandlesPaidAndInvalidLegacyBreaks() {
        val base = shift("2026-06-15T08:00", "2026-06-15T17:00")
        val unpaid = base.copy(
            breakStartEpochMillis = instant("2026-06-15T12:00").toEpochMilli(),
            breakEndEpochMillis = instant("2026-06-15T13:00").toEpochMilli(),
        )
        assertEquals(Duration.ofHours(8), unpaid.workedDuration())
        assertEquals(Duration.ofHours(9), unpaid.copy(breakPaid = true).workedDuration())
        assertEquals(Duration.ofHours(9), unpaid.copy(
            breakStartEpochMillis = unpaid.breakEndEpochMillis,
            breakEndEpochMillis = unpaid.breakStartEpochMillis,
        ).workedDuration())
    }
    @Test fun midnightCrossingSplitsEveningAndNightExactly() {
        val expected = 2 * settings.single().rate(ShiftType.EVENING) + 2 * settings.single().rate(ShiftType.NIGHT)
        assertEquals(expected, calculator.earnings(shift("2026-06-15T22:00", "2026-06-16T02:00"), settings), .001)
    }
    @Test fun weekendOverridesClockBands() {
        assertEquals(4 * settings.single().rate(ShiftType.WEEKEND), calculator.earnings(shift("2026-06-13T08:00", "2026-06-13T12:00"), settings), .001)
    }
    @Test fun holidayStartsInsideNightBand() {
        val expected = settings.single().rate(ShiftType.NIGHT) + settings.single().rate(ShiftType.HOLIDAY)
        assertEquals(expected, calculator.earnings(shift("2026-01-06T06:00", "2026-01-06T08:00"), settings), .001)
    }
    @Test fun majorHolidayStartsInsideNightBand() {
        val expected = settings.single().rate(ShiftType.NIGHT) + settings.single().rate(ShiftType.HOLIDAY_MAJOR)
        assertEquals(expected, calculator.earnings(shift("2026-12-24T06:00", "2026-12-24T08:00"), settings), .001)
    }
    @Test fun daylightSavingDurationsUseInstants() {
        assertEquals(settings.single().rate(ShiftType.WEEKEND), calculator.earnings(shift("2026-03-29T01:30", "2026-03-29T03:30"), settings), .001)
        assertEquals(3 * settings.single().rate(ShiftType.WEEKEND), calculator.earnings(shift("2026-10-25T01:30", "2026-10-25T03:30"), settings), .001)
    }
    @Test fun paidBreakRemainsIncluded() {
        val paid = shift("2026-06-15T08:00", "2026-06-15T17:00").copy(
            breakStartEpochMillis = instant("2026-06-15T12:00").toEpochMilli(),
            breakEndEpochMillis = instant("2026-06-15T13:00").toEpochMilli(),
            breakPaid = true,
        )
        assertEquals(9 * settings.single().rate(ShiftType.DAY), calculator.earnings(paid, settings), .001)
    }
    @Test fun reversedLegacyBreakDoesNotDoubleCount() {
        val legacy = shift("2026-06-15T08:00", "2026-06-15T17:00").copy(
            breakStartEpochMillis = instant("2026-06-15T13:00").toEpochMilli(),
            breakEndEpochMillis = instant("2026-06-15T12:00").toEpochMilli(),
        )
        assertEquals(9 * settings.single().rate(ShiftType.DAY), calculator.earnings(legacy, settings), .001)
    }
    @Test fun durationBreakdownReconcilesWithWorkedDuration() {
        val value = shift("2026-06-15T17:30", "2026-06-15T19:30")
        val durations = calculator.durationsByType(value)
        assertEquals(Duration.ofMinutes(30), durations.getValue(ShiftType.DAY))
        assertEquals(Duration.ofMinutes(90), durations.getValue(ShiftType.EVENING))
        assertEquals(value.workedDuration(), durations.values.fold(Duration.ZERO, Duration::plus))
    }
    @Test fun payBreakdownReconcilesWithNetEarnings() {
        val value = shift("2026-06-15T09:00", "2026-06-15T17:00")
        val breakdown = calculator.breakdown(value, settings)
        assertEquals(calculator.earnings(value, settings), breakdown.netPay, .000001)
        assertEquals(breakdown.taxableGross - breakdown.estimatedWithheldTax, breakdown.netPay, .000001)
        assertEquals(breakdown.grossPay * .125, breakdown.vacationPay, .000001)
    }
    @Test fun fractionalHoursKeepPrecisionUntilPresentation() {
        assertEquals(19.6875, calculator.earnings(shift("2026-06-15T09:00", "2026-06-15T09:15"), settings), .000001)
    }
    private fun shift(s: String, e: String) = ShiftEntity(startEpochMillis = instant(s).toEpochMilli(), endEpochMillis = instant(e).toEpochMilli())
    private fun period(rate: Double, s: String, e: String) = PayPeriodEntity(grossHourlyRate = rate, effectiveStartEpochMillis = instant(s).toEpochMilli(), effectiveEndEpochMillis = instant(e).toEpochMilli())
    private fun instant(v: String) = LocalDateTime.parse(v).atZone(zone).toInstant()
}
