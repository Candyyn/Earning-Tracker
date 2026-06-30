package studio.magnusson.livetracker.domain

import studio.magnusson.livetracker.data.PayPeriodEntity
import studio.magnusson.livetracker.data.ShiftEntity
import studio.magnusson.livetracker.data.ShiftType
import java.time.*
import java.time.temporal.TemporalAdjusters

class EarningsCalculator(private val fixedZone: ZoneId? = null) {
    fun earnings(shift: ShiftEntity, payPeriods: List<PayPeriodEntity>, workedUntil: Instant = shift.end): Double {
        return breakdown(shift, payPeriods, workedUntil).netPay
    }

    fun breakdown(shift: ShiftEntity, payPeriods: List<PayPeriodEntity>, workedUntil: Instant = shift.end): EarningsBreakdown {
        val end = minOf(workedUntil, shift.end)
        if (!shift.start.isBefore(end)) return EarningsBreakdown()
        val ranges = workRanges(shift, end)
        return ranges.fold(EarningsBreakdown()) { totalBreakdown, (start, finish) ->
            var cursor = start
            var total = EarningsBreakdown()
            while (cursor < finish) {
                val period = payPeriods.firstOrNull { it.contains(cursor) }
                val next = listOfNotNull(
                    finish,
                    nextScheduleBoundary(cursor),
                    period?.effectiveEnd,
                    payPeriods.asSequence().map { it.effectiveStart }.filter { it > cursor }.minOrNull(),
                ).filter { it > cursor }.minOrNull() ?: finish
                val hours = Duration.between(cursor, next).toNanos() / 3_600_000_000_000.0
                period?.rateBreakdown(typeAt(cursor))?.let { rate ->
                    total += EarningsBreakdown(
                        grossPay = rate.grossPay * hours,
                        vacationPay = rate.vacationPay * hours,
                        estimatedWithheldTax = rate.estimatedWithheldTax * hours,
                        netPay = rate.netPay * hours,
                    )
                }
                cursor = next
            }
            totalBreakdown + total
        }
    }

    fun durationsByType(shift: ShiftEntity, workedUntil: Instant = shift.end): Map<ShiftType, Duration> {
        val end = minOf(workedUntil, shift.end)
        val durations = ShiftType.entries.associateWith { Duration.ZERO }.toMutableMap()
        if (!shift.start.isBefore(end)) return durations
        workRanges(shift, end).forEach { (start, finish) ->
            var cursor = start
            while (cursor < finish) {
                val next = minOf(finish, nextScheduleBoundary(cursor))
                val type = typeAt(cursor)
                durations[type] = durations.getValue(type).plus(Duration.between(cursor, next))
                cursor = next
            }
        }
        return durations
    }

    private fun workRanges(shift: ShiftEntity, end: Instant): List<Pair<Instant, Instant>> {
        val ranges = mutableListOf(shift.start to end)
        if (!shift.breakPaid && shift.breakStartEpochMillis != null && shift.breakEndEpochMillis != null &&
            shift.breakStartEpochMillis < shift.breakEndEpochMillis
        ) {
            val bs = Instant.ofEpochMilli(shift.breakStartEpochMillis).coerceIn(shift.start, end)
            val be = Instant.ofEpochMilli(shift.breakEndEpochMillis).coerceIn(shift.start, end)
            ranges.clear()
            if (shift.start < bs) ranges += shift.start to bs
            if (be < end) ranges += be to end
        }
        return ranges
    }

    fun dominantType(shift: ShiftEntity): ShiftType {
        if (!shift.start.isBefore(shift.end)) return ShiftType.DAY
        val durations = ShiftType.entries.associateWith { Duration.ZERO }.toMutableMap()
        var cursor = shift.start
        while (cursor < shift.end) {
            val next = minOf(shift.end, nextScheduleBoundary(cursor))
            val type = typeAt(cursor)
            durations[type] = durations.getValue(type).plus(Duration.between(cursor, next))
            cursor = next
        }
        if (durations.getValue(ShiftType.HOLIDAY_MAJOR) > Duration.ZERO) return ShiftType.HOLIDAY_MAJOR
        if (durations.getValue(ShiftType.HOLIDAY) > Duration.ZERO) return ShiftType.HOLIDAY
        if (durations.getValue(ShiftType.WEEKEND) > Duration.ZERO &&
            durations.getValue(ShiftType.DAY).isZero &&
            durations.getValue(ShiftType.EVENING).isZero &&
            durations.getValue(ShiftType.NIGHT).isZero
        ) return ShiftType.WEEKEND
        return listOf(ShiftType.DAY, ShiftType.EVENING, ShiftType.NIGHT, ShiftType.WEEKEND)
            .maxBy { durations.getValue(it) }
    }

    private fun nextScheduleBoundary(after: Instant): Instant {
        val zone = fixedZone ?: ZoneId.systemDefault()
        val local = after.atZone(zone)
        val dates = (local.year - 1..local.year + 1).flatMap { HolidayCalendar.boundaries(it, zone) }
        val clockBoundaries = listOf(0, 8, 18).map { hour ->
            var candidate = local.toLocalDate().atTime(hour, 0).atZone(zone)
            if (!candidate.toInstant().isAfter(after)) candidate = local.toLocalDate().plusDays(1).atTime(hour, 0).atZone(zone)
            candidate.toInstant()
        }
        return (clockBoundaries + dates).filter { it > after }.minOrNull()
            ?: after.plus(Duration.ofDays(1))
    }

    fun typeAt(instant: Instant): ShiftType {
        val zone = fixedZone ?: ZoneId.systemDefault()
        val time = instant.atZone(zone)
        if (HolidayCalendar.isMajor(time)) return ShiftType.HOLIDAY_MAJOR
        if (HolidayCalendar.isHoliday(time)) return ShiftType.HOLIDAY
        return when {
            time.dayOfWeek == DayOfWeek.SATURDAY || time.dayOfWeek == DayOfWeek.SUNDAY -> ShiftType.WEEKEND
            time.hour in 8..<18 -> ShiftType.DAY
            time.hour >= 18 -> ShiftType.EVENING
            else -> ShiftType.NIGHT
        }
    }
}

data class EarningsBreakdown(
    val grossPay: Double = 0.0,
    val vacationPay: Double = 0.0,
    val estimatedWithheldTax: Double = 0.0,
    val netPay: Double = 0.0,
) {
    val taxableGross get() = grossPay + vacationPay
    operator fun plus(other: EarningsBreakdown) = EarningsBreakdown(
        grossPay + other.grossPay,
        vacationPay + other.vacationPay,
        estimatedWithheldTax + other.estimatedWithheldTax,
        netPay + other.netPay,
    )
}

object HolidayCalendar {
    fun boundaries(year: Int, zone: ZoneId = ZoneId.systemDefault()): List<Instant> {
        val easter = easterSunday(year)
        val midsummer = LocalDate.of(year, 6, 19).with(TemporalAdjusters.nextOrSame(DayOfWeek.FRIDAY))
        val ranges = mutableListOf<Pair<ZonedDateTime, ZonedDateTime>>()
        listOf(
            LocalDate.of(year, 1, 6), easter.plusDays(39), LocalDate.of(year, 5, 1),
            LocalDate.of(year, 10, 31).with(TemporalAdjusters.nextOrSame(DayOfWeek.SATURDAY)),
            LocalDate.of(year, 6, 6),
        ).forEach { day -> ranges += day.atTime(7, 0).atZone(zone) to nextWeekday(day).atStartOfDay(zone) }
        listOf(
            Triple(easter.minusDays(3), 18, easter.plusDays(1)),
            Triple(easter.plusDays(48), 7, easter.plusDays(49)),
            Triple(midsummer, 7, midsummer.plusDays(1)),
            Triple(LocalDate.of(year, 12, 24), 7, LocalDate.of(year, 12, 26)),
            Triple(LocalDate.of(year, 12, 31), 7, LocalDate.of(year + 1, 1, 1)),
        ).forEach { (start, hour, end) -> ranges += start.atTime(hour, 0).atZone(zone) to nextWeekday(end).atStartOfDay(zone) }
        return ranges.flatMap { listOf(it.first.toInstant(), it.second.toInstant()) }.distinct()
    }

    fun isHoliday(time: ZonedDateTime): Boolean {
        return (time.year - 1..time.year + 1).any { year ->
            val easter = easterSunday(year)
            val days = listOf(
                LocalDate.of(year, 1, 6), easter.plusDays(39), LocalDate.of(year, 5, 1),
                LocalDate.of(year, 10, 31).with(TemporalAdjusters.nextOrSame(DayOfWeek.SATURDAY)),
                LocalDate.of(year, 6, 6),
            )
            days.any { day -> time >= day.atTime(7, 0).atZone(time.zone) && time < nextWeekday(day).atStartOfDay(time.zone) }
        }
    }

    fun isMajor(time: ZonedDateTime): Boolean {
        return (time.year - 1..time.year + 1).any { year ->
            val easter = easterSunday(year)
            val midsummer = LocalDate.of(year, 6, 19).with(TemporalAdjusters.nextOrSame(DayOfWeek.FRIDAY))
            listOf(
                Triple(easter.minusDays(3), 18, easter.plusDays(1)),
                Triple(easter.plusDays(48), 7, easter.plusDays(49)),
                Triple(midsummer, 7, midsummer.plusDays(1)),
                Triple(LocalDate.of(year, 12, 24), 7, LocalDate.of(year, 12, 26)),
                Triple(LocalDate.of(year, 12, 31), 7, LocalDate.of(year + 1, 1, 1)),
            ).any { (start, hour, lastHoliday) ->
                time >= start.atTime(hour, 0).atZone(time.zone) && time < nextWeekday(lastHoliday).atStartOfDay(time.zone)
            }
        }
    }

    private fun nextWeekday(date: LocalDate): LocalDate {
        var candidate = date.plusDays(1)
        while (candidate.dayOfWeek in setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)) candidate = candidate.plusDays(1)
        return candidate
    }

    fun easterSunday(year: Int): LocalDate {
        val a = year % 19; val b = year / 100; val c = year % 100; val d = b / 4; val e = b % 4
        val f = (b + 8) / 25; val g = (b - f + 1) / 3; val h = (19 * a + b - d - g + 15) % 30
        val i = c / 4; val k = c % 4; val l = (32 + 2 * e + 2 * i - h - k) % 7
        val m = (a + 11 * h + 22 * l) / 451
        val month = (h + l - 7 * m + 114) / 31
        val day = (h + l - 7 * m + 114) % 31 + 1
        return LocalDate.of(year, month, day)
    }
}

private fun Instant.coerceIn(min: Instant, max: Instant) = when { this < min -> min; this > max -> max; else -> this }
