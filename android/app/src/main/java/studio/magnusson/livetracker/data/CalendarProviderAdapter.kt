package studio.magnusson.livetracker.data

import android.content.ContentUris
import android.content.ContentProviderOperation
import android.content.ContentValues
import android.content.Context
import android.provider.CalendarContract
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.TimeZone
import java.util.UUID

data class CalendarShiftRecord(
    val id: String,
    val startEpochMillis: Long,
    val endEpochMillis: Long,
    val breakStartEpochMillis: Long?,
    val breakEndEpochMillis: Long?,
    val breakPaid: Boolean,
    val eventIds: String,
    val syncIdentifier: String,
)

data class CalendarEventLink(val eventIds: String, val syncIdentifier: String)

interface CalendarGateway {
    fun save(shift: ShiftEntity): CalendarEventLink
    fun delete(shift: ShiftEntity)
    fun fetch(start: Instant, end: Instant): List<CalendarShiftRecord>
}

class CalendarProviderAdapter(private val context: Context) : CalendarGateway {
    private val resolver get() = context.contentResolver

    override fun save(shift: ShiftEntity): CalendarEventLink {
        val calendar = writableCalendar()
        val uri = shiftUri(shift.id)
        val existingIds = linkedSetOf<Long>()
        shift.calendarEventId?.split(';')?.mapNotNull(String::toLongOrNull)?.filterTo(existingIds, ::eventExists)
        queryEventIds(uri).forEach(existingIds::add)
        val existing = existingIds.toList()
        val targets = targets(shift)
        val operations = mutableListOf<ContentProviderOperation>()
        targets.forEachIndexed { index, target ->
            val values = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendar.id)
                put(CalendarContract.Events.TITLE, target.title)
                put(CalendarContract.Events.DTSTART, target.start)
                put(CalendarContract.Events.DTEND, target.end)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                put(CalendarContract.Events.CUSTOM_APP_PACKAGE, context.packageName)
                put(CalendarContract.Events.CUSTOM_APP_URI, uri)
            }
            val operation = existing.getOrNull(index)?.let {
                ContentProviderOperation.newUpdate(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, it)).withValues(values).build()
            } ?: ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI).withValues(values).build()
            operations += operation
        }
        existing.drop(targets.size).forEach {
            operations += ContentProviderOperation.newDelete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, it)).build()
        }
        val results = resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(operations))
        val finalIds = targets.indices.map { index ->
            existing.getOrNull(index) ?: results[index].uri?.lastPathSegment?.toLongOrNull()
            ?: error("Calendar provider did not return an event ID")
        }
        return CalendarEventLink(finalIds.joinToString(";"), syncIdentifier(shift.id))
    }

    override fun delete(shift: ShiftEntity) {
        val ids = linkedSetOf<Long>()
        shift.calendarEventId?.split(';')?.mapNotNullTo(ids, String::toLongOrNull)
        queryEventIds(shiftUri(shift.id)).forEach(ids::add)
        if (ids.isNotEmpty()) resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(ids.map {
            ContentProviderOperation.newDelete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, it)).build()
        }))
    }

    override fun fetch(start: Instant, end: Instant): List<CalendarShiftRecord> {
        val calendar = writableCalendar()
        val columns = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.CUSTOM_APP_URI,
        )
        val grouped = linkedMapOf<String, MutableList<ProviderEvent>>()
        val cursor = resolver.query(
            CalendarContract.Events.CONTENT_URI,
            columns,
            "${CalendarContract.Events.CALENDAR_ID}=? AND ${CalendarContract.Events.DTSTART}<? AND ${CalendarContract.Events.DTEND}>? AND ${CalendarContract.Events.DELETED}=0",
            arrayOf(calendar.id.toString(), end.toEpochMilli().toString(), start.toEpochMilli().toString()),
            "${CalendarContract.Events.DTSTART} ASC",
        ) ?: throw IllegalStateException("Calendar provider query failed")
        cursor.use {
            while (cursor.moveToNext()) {
                val event = ProviderEvent(cursor.getLong(0), cursor.getString(1).orEmpty(), cursor.getLong(2), cursor.getLong(3), cursor.getString(4))
                val taggedId = event.appUri?.takeIf { it.startsWith(SHIFT_URI_PREFIX) }?.removePrefix(SHIFT_URI_PREFIX)
                if (taggedId != null) grouped.getOrPut("app:$taggedId") { mutableListOf() } += event
                else if (calendar.dedicated) grouped["native:${event.id}"] = mutableListOf(event)
            }
        }
        return grouped.mapNotNull { (key, events) ->
            val first = events.minByOrNull { it.start } ?: return@mapNotNull null
            val taggedId = key.removePrefix("app:").takeIf { key.startsWith("app:") }
            val id = taggedId ?: UUID.nameUUIDFromBytes("calendar:${first.id}".toByteArray(StandardCharsets.UTF_8)).toString()
            val breakEvent = events.firstOrNull { it.title == PAID_BREAK || it.title == UNPAID_BREAK }
            CalendarShiftRecord(
                id = id,
                startEpochMillis = events.minOf { it.start },
                endEpochMillis = events.maxOf { it.end },
                breakStartEpochMillis = breakEvent?.start,
                breakEndEpochMillis = breakEvent?.end,
                breakPaid = breakEvent?.title == PAID_BREAK,
                eventIds = events.joinToString(";") { it.id.toString() },
                syncIdentifier = taggedId?.let(::syncIdentifier) ?: "calendar:${first.id}",
            )
        }.filter { it.startEpochMillis < it.endEpochMillis && it.endEpochMillis > start.toEpochMilli() && it.startEpochMillis < end.toEpochMilli() }
    }

    private fun queryEventIds(appUri: String): List<Long> {
        val result = mutableListOf<Long>()
        val cursor = resolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID),
            "${CalendarContract.Events.CUSTOM_APP_URI}=? AND ${CalendarContract.Events.DELETED}=0",
            arrayOf(appUri),
            null,
        ) ?: throw IllegalStateException("Calendar provider query failed")
        cursor.use { while (it.moveToNext()) result += it.getLong(0) }
        return result
    }

    private fun eventExists(id: Long): Boolean {
        val cursor = resolver.query(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id),
            arrayOf(CalendarContract.Events._ID),
            "${CalendarContract.Events.DELETED}=0",
            null,
            null,
        ) ?: throw IllegalStateException("Calendar provider query failed")
        return cursor.use { it.moveToFirst() }
    }

    private fun writableCalendar(): ProviderCalendar {
        findWritableCalendar(preferDedicated = true)?.takeIf { it.dedicated }?.let { return it }
        runCatching { createDedicatedCalendar() }
        return findWritableCalendar(preferDedicated = true)
            ?: throw IllegalStateException("No writable calendar is available")
    }

    private fun findWritableCalendar(preferDedicated: Boolean): ProviderCalendar? {
        val calendars = mutableListOf<ProviderCalendar>()
        val cursor = resolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME),
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=? AND ${CalendarContract.Calendars.VISIBLE}=1",
            arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            null,
        ) ?: throw IllegalStateException("Calendar provider query failed")
        cursor.use {
            while (cursor.moveToNext()) calendars += ProviderCalendar(cursor.getLong(0), cursor.getString(1) == CALENDAR_NAME)
        }
        return if (preferDedicated) calendars.firstOrNull { it.dedicated } ?: calendars.firstOrNull() else calendars.firstOrNull()
    }

    private fun createDedicatedCalendar() {
        val accountName = context.packageName
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, CALENDAR_NAME)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, CALENDAR_NAME)
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xff7b1fa2.toInt())
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, accountName)
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
        }
        val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()
        requireNotNull(resolver.insert(uri, values)) { "Unable to create Shifts calendar" }
    }

    private fun targets(shift: ShiftEntity): List<EventTarget> {
        val breakStart = shift.breakStartEpochMillis
        val breakEnd = shift.breakEndEpochMillis
        if (breakStart == null || breakEnd == null || breakStart >= breakEnd) return listOf(EventTarget(WORK, shift.startEpochMillis, shift.endEpochMillis))
        return buildList {
            if (shift.startEpochMillis < breakStart) add(EventTarget(WORK, shift.startEpochMillis, minOf(breakStart, shift.endEpochMillis)))
            add(EventTarget(if (shift.breakPaid) PAID_BREAK else UNPAID_BREAK, breakStart, breakEnd))
            if (breakEnd < shift.endEpochMillis) add(EventTarget(WORK, maxOf(breakEnd, shift.startEpochMillis), shift.endEpochMillis))
        }
    }

    private fun shiftUri(id: String) = "$SHIFT_URI_PREFIX$id"
    private fun syncIdentifier(id: String) = "livetracker:$id"
    private data class ProviderCalendar(val id: Long, val dedicated: Boolean)
    private data class ProviderEvent(val id: Long, val title: String, val start: Long, val end: Long, val appUri: String?)
    private data class EventTarget(val title: String, val start: Long, val end: Long)

    private companion object {
        const val CALENDAR_NAME = "Shifts"
        const val SHIFT_URI_PREFIX = "livetracker://shift/"
        const val WORK = "Work Shift"
        const val PAID_BREAK = "Break (Paid)"
        const val UNPAID_BREAK = "Break (Unpaid)"
    }
}
