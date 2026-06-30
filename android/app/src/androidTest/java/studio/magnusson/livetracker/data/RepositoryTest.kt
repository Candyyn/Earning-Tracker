package studio.magnusson.livetracker.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import studio.magnusson.livetracker.domain.EarningsCalculator
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class RepositoryTest {
    private lateinit var database: LiveTrackerDatabase

    @Before fun createDatabase() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), LiveTrackerDatabase::class.java)
            .allowMainThreadQueries().build()
    }

    @After fun closeDatabase() = database.close()

    @Test fun splittingAndDeletingPeriodsPreservesContinuousTimeline() = runTest {
        val initial = PayPeriodEntity(id = "initial", grossHourlyRate = 100.0, effectiveStartEpochMillis = 0, effectiveEndEpochMillis = 10_000)
        database.payPeriodDao().upsert(initial)
        val repository = PayPeriodRepository(database)
        val secondId = repository.splitPeriod(initial.id, Instant.ofEpochMilli(4_000))
        var periods = repository.periods.first()
        assertEquals(periods[0].effectiveEndEpochMillis, periods[1].effectiveStartEpochMillis)
        repository.deletePeriod(secondId)
        periods = repository.periods.first()
        assertEquals(1, periods.size)
        assertEquals(10_000, periods.single().effectiveEndEpochMillis)
    }

    @Test fun editingBoundaryAdjustsAdjacentPeriod() = runTest {
        val first = PayPeriodEntity(id = "first", grossHourlyRate = 100.0, effectiveStartEpochMillis = 0, effectiveEndEpochMillis = 5_000)
        val second = PayPeriodEntity(id = "second", grossHourlyRate = 120.0, effectiveStartEpochMillis = 5_000, effectiveEndEpochMillis = 10_000)
        database.payPeriodDao().upsert(first); database.payPeriodDao().upsert(second)
        val repository = PayPeriodRepository(database)
        repository.updateStart(second.id, Instant.ofEpochMilli(6_000))
        val periods = repository.periods.first()
        assertEquals(6_000, periods[0].effectiveEndEpochMillis)
        assertEquals(6_000, periods[1].effectiveStartEpochMillis)
    }

    @Test fun calendarFailureDoesNotMutateKnownEventIds() = runTest {
        val shift = ShiftEntity(id = "shift", startEpochMillis = 1_000, endEpochMillis = 2_000, calendarEventId = "known")
        database.shiftDao().upsert(shift)
        val failing = object : CalendarGateway {
            override fun save(shift: ShiftEntity): CalendarEventLink = error("provider failed")
            override fun delete(shift: ShiftEntity) = Unit
            override fun fetch(start: Instant, end: Instant) = emptyList<CalendarShiftRecord>()
        }
        val repository = CalendarSyncRepository(database, failing, EarningsCalculator())
        runCatching { repository.save(shift.copy(startEpochMillis = 1_100)) }
        val stored = database.shiftDao().getBetween(0, 3_000).single()
        assertEquals("known", stored.calendarEventId)
        assertNull(stored.calendarSyncIdentifier)
    }

    @Test fun calendarSyncDeletesProviderRemovedShiftAndExportsUnsyncedShift() = runTest {
        val reference = Instant.parse("2026-06-15T12:00:00Z")
        val removed = ShiftEntity(
            id = "removed",
            startEpochMillis = Instant.parse("2026-06-10T08:00:00Z").toEpochMilli(),
            endEpochMillis = Instant.parse("2026-06-10T16:00:00Z").toEpochMilli(),
            calendarEventId = "10",
            calendarSyncIdentifier = "livetracker:removed",
        )
        val unsynced = ShiftEntity(
            id = "unsynced",
            startEpochMillis = Instant.parse("2026-06-11T08:00:00Z").toEpochMilli(),
            endEpochMillis = Instant.parse("2026-06-11T16:00:00Z").toEpochMilli(),
        )
        database.shiftDao().upsert(removed)
        database.shiftDao().upsert(unsynced)
        val gateway = object : CalendarGateway {
            override fun save(shift: ShiftEntity) = CalendarEventLink("20", "livetracker:${shift.id}")
            override fun delete(shift: ShiftEntity) = Unit
            override fun fetch(start: Instant, end: Instant) = emptyList<CalendarShiftRecord>()
        }
        CalendarSyncRepository(database, gateway, EarningsCalculator()).synchronize(reference)
        val shifts = database.shiftDao().getBetween(
            Instant.parse("2026-05-01T00:00:00Z").toEpochMilli(),
            Instant.parse("2026-08-01T00:00:00Z").toEpochMilli(),
        )
        assertEquals(listOf("unsynced"), shifts.map { it.id })
        assertEquals("20", shifts.single().calendarEventId)
        assertEquals("livetracker:unsynced", shifts.single().calendarSyncIdentifier)
    }

    @Test fun calendarSyncMatchesCrossBoundaryShiftByStableIdentifier() = runTest {
        val reference = Instant.parse("2026-06-15T12:00:00Z")
        val existing = ShiftEntity(
            id = "local-id",
            startEpochMillis = Instant.parse("2026-04-30T20:00:00Z").toEpochMilli(),
            endEpochMillis = Instant.parse("2026-05-01T06:00:00Z").toEpochMilli(),
            calendarEventId = "old-event",
            calendarSyncIdentifier = "calendar:stable",
        )
        database.shiftDao().upsert(existing)
        val fetched = CalendarShiftRecord(
            id = "different-id",
            startEpochMillis = existing.startEpochMillis,
            endEpochMillis = existing.endEpochMillis + 3_600_000,
            breakStartEpochMillis = null,
            breakEndEpochMillis = null,
            breakPaid = false,
            eventIds = "new-event",
            syncIdentifier = "calendar:stable",
        )
        val gateway = object : CalendarGateway {
            override fun save(shift: ShiftEntity) = CalendarEventLink("saved", "livetracker:${shift.id}")
            override fun delete(shift: ShiftEntity) = Unit
            override fun fetch(start: Instant, end: Instant) = listOf(fetched)
        }
        CalendarSyncRepository(database, gateway, EarningsCalculator()).synchronize(reference)
        val stored = database.shiftDao().getBetween(
            Instant.parse("2026-04-01T00:00:00Z").toEpochMilli(),
            Instant.parse("2026-06-01T00:00:00Z").toEpochMilli(),
        ).single()
        assertEquals("local-id", stored.id)
        assertEquals("new-event", stored.calendarEventId)
        assertEquals(fetched.endEpochMillis, stored.endEpochMillis)
    }
}
