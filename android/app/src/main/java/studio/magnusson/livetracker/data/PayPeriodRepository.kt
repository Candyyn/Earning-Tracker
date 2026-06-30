package studio.magnusson.livetracker.data

import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID

class PayPeriodRepository(private val database: LiveTrackerDatabase) {
    private val dao = database.payPeriodDao()
    val periods: Flow<List<PayPeriodEntity>> = dao.observeAll()

    suspend fun updateRate(id: String, rate: Double) = database.withTransaction {
        val period = dao.getAll().firstOrNull { it.id == id } ?: return@withTransaction
        dao.upsert(period.copy(grossHourlyRate = rate.takeIf(Double::isFinite)?.coerceAtLeast(0.0) ?: 0.0))
    }

    suspend fun splitPeriod(id: String, start: Instant): String = database.withTransaction {
        val periods = dao.getAll()
        val source = periods.firstOrNull { it.id == id } ?: error("Pay period not found")
        require(start.isAfter(source.effectiveStart) && start.isBefore(source.effectiveEnd)) {
            "New pay period must start inside an existing period"
        }
        val newId = UUID.randomUUID().toString()
        dao.upsert(source.copy(effectiveEndEpochMillis = start.toEpochMilli()))
        dao.upsert(
            PayPeriodEntity(
                id = newId,
                grossHourlyRate = source.grossHourlyRate,
                effectiveStartEpochMillis = start.toEpochMilli(),
                effectiveEndEpochMillis = source.effectiveEndEpochMillis,
            )
        )
        newId
    }

    suspend fun deletePeriod(id: String) = database.withTransaction {
        val periods = dao.getAll()
        require(periods.size > 1) { "The final pay period cannot be deleted" }
        val index = periods.indexOfFirst { it.id == id }
        require(index >= 0) { "Pay period not found" }
        val deleted = periods[index]
        if (index > 0) {
            dao.upsert(periods[index - 1].copy(effectiveEndEpochMillis = deleted.effectiveEndEpochMillis))
        } else {
            dao.upsert(periods[index + 1].copy(effectiveStartEpochMillis = deleted.effectiveStartEpochMillis))
        }
        dao.delete(deleted)
    }

    suspend fun updateStart(id: String, start: Instant) = database.withTransaction {
        val periods = dao.getAll()
        val index = periods.indexOfFirst { it.id == id }
        require(index >= 0) { "Pay period not found" }
        val period = periods[index]
        require(start.isBefore(period.effectiveEnd)) { "Start date must be before end date" }
        if (index > 0) {
            val previous = periods[index - 1]
            require(start.isAfter(previous.effectiveStart)) { "Start date overlaps previous pay period" }
            dao.upsert(previous.copy(effectiveEndEpochMillis = start.toEpochMilli()))
        }
        dao.upsert(period.copy(effectiveStartEpochMillis = start.toEpochMilli()))
    }

    suspend fun updateEnd(id: String, end: Instant) = database.withTransaction {
        val periods = dao.getAll()
        val index = periods.indexOfFirst { it.id == id }
        require(index >= 0) { "Pay period not found" }
        val period = periods[index]
        require(end.isAfter(period.effectiveStart)) { "End date must be after start date" }
        if (index < periods.lastIndex) {
            val next = periods[index + 1]
            require(end.isBefore(next.effectiveEnd)) { "End date overlaps next pay period" }
            dao.upsert(next.copy(effectiveStartEpochMillis = end.toEpochMilli()))
        }
        dao.upsert(period.copy(effectiveEndEpochMillis = end.toEpochMilli()))
    }

    suspend fun updateRange(id: String, start: Instant, end: Instant) = database.withTransaction {
        val periods = dao.getAll()
        val index = periods.indexOfFirst { it.id == id }
        require(index >= 0) { "Pay period not found" }
        require(start.isBefore(end)) { "Start date must be before end date" }
        periods.getOrNull(index - 1)?.let { previous ->
            require(start.isAfter(previous.effectiveStart)) { "Start date overlaps previous pay period" }
            dao.upsert(previous.copy(effectiveEndEpochMillis = start.toEpochMilli()))
        }
        periods.getOrNull(index + 1)?.let { next ->
            require(end.isBefore(next.effectiveEnd)) { "End date overlaps next pay period" }
            dao.upsert(next.copy(effectiveStartEpochMillis = end.toEpochMilli()))
        }
        dao.upsert(periods[index].copy(effectiveStartEpochMillis = start.toEpochMilli(), effectiveEndEpochMillis = end.toEpochMilli()))
    }
}
