package studio.magnusson.livetracker.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.util.UUID

enum class ShiftType { DAY, EVENING, NIGHT, WEEKEND, HOLIDAY, HOLIDAY_MAJOR }

@Entity(tableName = "shifts")
data class ShiftEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val startEpochMillis: Long,
    val endEpochMillis: Long,
    val breakStartEpochMillis: Long? = null,
    val breakEndEpochMillis: Long? = null,
    val breakPaid: Boolean = false,
    val calendarEventId: String? = null,
    val calendarSyncIdentifier: String? = null,
    val dominantShiftType: ShiftType = ShiftType.DAY,
) {
    val start: Instant get() = Instant.ofEpochMilli(startEpochMillis)
    val end: Instant get() = Instant.ofEpochMilli(endEpochMillis)

    fun workedDuration(until: Instant = end): java.time.Duration {
        val effectiveEnd = minOf(until, end)
        if (!start.isBefore(effectiveEnd)) return java.time.Duration.ZERO
        val total = java.time.Duration.between(start, effectiveEnd)
        if (breakPaid || breakStartEpochMillis == null || breakEndEpochMillis == null ||
            breakStartEpochMillis >= breakEndEpochMillis
        ) return total
        val breakStart = Instant.ofEpochMilli(breakStartEpochMillis).coerceIn(start, effectiveEnd)
        val breakEnd = Instant.ofEpochMilli(breakEndEpochMillis).coerceIn(start, effectiveEnd)
        return total.minus(java.time.Duration.between(breakStart, breakEnd))
    }
}

private fun Instant.coerceIn(min: Instant, max: Instant) = when {
    this < min -> min
    this > max -> max
    else -> this
}

@Entity(
    tableName = "pay_periods",
    indices = [Index(value = ["effectiveStartEpochMillis"], unique = true)]
)
data class PayPeriodEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val grossHourlyRate: Double,
    val effectiveStartEpochMillis: Long,
    val effectiveEndEpochMillis: Long,
) {
    init {
        require(effectiveStartEpochMillis < effectiveEndEpochMillis) { "Pay period must have a positive range" }
    }

    val effectiveStart: Instant get() = Instant.ofEpochMilli(effectiveStartEpochMillis)
    val effectiveEnd: Instant get() = Instant.ofEpochMilli(effectiveEndEpochMillis)

    fun contains(instant: Instant) = !instant.isBefore(effectiveStart) && instant.isBefore(effectiveEnd)

    fun rate(type: ShiftType): Double {
        if (!grossHourlyRate.isFinite() || grossHourlyRate <= 0) return 0.0
        return grossRate(type) * (1.0 + VACATION_BONUS_RATE) * (1.0 - TAX_RATE)
    }

    fun rateBreakdown(type: ShiftType): PayRateBreakdown {
        val gross = grossRate(type)
        val vacation = gross * VACATION_BONUS_RATE
        val net = rate(type)
        return PayRateBreakdown(gross, vacation, (gross + vacation - net).coerceAtLeast(0.0), net)
    }

    private fun grossRate(type: ShiftType): Double {
        if (!grossHourlyRate.isFinite() || grossHourlyRate <= 0) return 0.0
        val divisor = when (type) {
            ShiftType.DAY -> null
            ShiftType.EVENING -> 600.0
            ShiftType.NIGHT -> 400.0
            ShiftType.WEEKEND, ShiftType.HOLIDAY -> 300.0
            ShiftType.HOLIDAY_MAJOR -> 150.0
        }
        return grossHourlyRate + (divisor?.let { grossHourlyRate * 160.0 / it } ?: 0.0)
    }

    companion object {
        private const val VACATION_BONUS_RATE = 0.125
        private const val TAX_RATE = 0.3
    }
}

data class PayRateBreakdown(
    val grossPay: Double,
    val vacationPay: Double,
    val estimatedWithheldTax: Double,
    val netPay: Double,
)
