package studio.magnusson.livetracker.data

import androidx.room.withTransaction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import studio.magnusson.livetracker.domain.EarningsCalculator
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

class CalendarSyncRepository(
    private val database: LiveTrackerDatabase,
    private val adapter: CalendarGateway,
    private val calculator: EarningsCalculator,
) {
    private val dao = database.shiftDao()

    suspend fun save(shift: ShiftEntity): ShiftEntity = withContext(Dispatchers.IO) {
        val link = adapter.save(shift)
        shift.copy(calendarEventId = link.eventIds, calendarSyncIdentifier = link.syncIdentifier)
    }

    suspend fun delete(shift: ShiftEntity) = withContext(Dispatchers.IO) { adapter.delete(shift) }

    suspend fun synchronize(reference: Instant = Instant.now()) = withContext(Dispatchers.IO) {
        val zone = ZoneId.systemDefault()
        val month = YearMonth.from(reference.atZone(zone))
        val start = month.minusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
        val end = month.plusMonths(2).atDay(1).atStartOfDay(zone).toInstant()
        val fetched = adapter.fetch(start, end)
        database.withTransaction {
            val existing = dao.getBetween(start.toEpochMilli(), end.toEpochMilli())
            val byId = existing.associateBy { it.id }
            val bySync = existing.mapNotNull { shift -> shift.calendarSyncIdentifier?.let { it to shift } }.toMap()
            val byEvent = existing.flatMap { shift -> shift.calendarEventId?.split(';')?.map { it to shift }.orEmpty() }.toMap()
            val matched = mutableSetOf<String>()
            fetched.forEach { record ->
                val match = byId[record.id] ?: bySync[record.syncIdentifier]
                    ?: record.eventIds.split(';').firstNotNullOfOrNull(byEvent::get)
                val updated = ShiftEntity(
                    id = match?.id ?: record.id,
                    startEpochMillis = record.startEpochMillis,
                    endEpochMillis = record.endEpochMillis,
                    breakStartEpochMillis = record.breakStartEpochMillis,
                    breakEndEpochMillis = record.breakEndEpochMillis,
                    breakPaid = record.breakPaid,
                    calendarEventId = record.eventIds,
                    calendarSyncIdentifier = record.syncIdentifier,
                ).let { it.copy(dominantShiftType = calculator.dominantType(it)) }
                dao.upsert(updated)
                matched += updated.id
            }
            existing.filter { (it.calendarEventId != null || it.calendarSyncIdentifier != null) && it.id !in matched }
                .forEach { dao.delete(it) }
        }
        dao.getBetween(start.toEpochMilli(), end.toEpochMilli())
            .filter { it.calendarEventId == null && it.calendarSyncIdentifier == null }
            .forEach { shift ->
                val link = adapter.save(shift)
                dao.upsert(shift.copy(calendarEventId = link.eventIds, calendarSyncIdentifier = link.syncIdentifier))
            }
    }
}
