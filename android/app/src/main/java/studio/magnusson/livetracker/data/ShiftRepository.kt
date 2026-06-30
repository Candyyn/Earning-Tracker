package studio.magnusson.livetracker.data

import kotlinx.coroutines.flow.Flow
import studio.magnusson.livetracker.domain.EarningsCalculator

class ShiftRepository(
    private val dao: ShiftDao,
    private val calculator: EarningsCalculator,
) {
    val shifts: Flow<List<ShiftEntity>> = dao.observeAll()

    suspend fun save(shift: ShiftEntity) {
        require(shift.start.isBefore(shift.end)) { "Shift must end after it starts" }
        require(validBreak(shift)) { "Break must be inside shift and end after it starts" }
        dao.upsert(shift.copy(dominantShiftType = calculator.dominantType(shift)))
    }

    suspend fun delete(shift: ShiftEntity) = dao.delete(shift)

    private fun validBreak(shift: ShiftEntity): Boolean {
        val start = shift.breakStartEpochMillis
        val end = shift.breakEndEpochMillis
        if (start == null && end == null) return true
        if (start == null || end == null) return false
        return start >= shift.startEpochMillis && start < end && end <= shift.endEpochMillis
    }
}
