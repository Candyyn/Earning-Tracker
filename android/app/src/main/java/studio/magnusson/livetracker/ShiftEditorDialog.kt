package studio.magnusson.livetracker

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import studio.magnusson.livetracker.data.ShiftEntity
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.UUID

private enum class EditorPicker { DATE, START, END, BREAK_START, BREAK_END }
private fun LocalTime.toMinuteOfDay() = hour * 60 + minute

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun NativeShiftEditor(
    existing: ShiftEntity?,
    newShiftDate: LocalDate = LocalDate.now(),
    dismiss: () -> Unit,
    save: (ShiftEntity) -> Unit,
) {
    val zone = ZoneId.systemDefault()
    val currentTime = LocalTime.now().withSecond(0).withNano(0)
    val initialStart = existing?.start?.atZone(zone) ?: newShiftDate.atTime(currentTime).atZone(zone)
    val initialEnd = existing?.end?.atZone(zone) ?: initialStart.plusHours(8)
    val defaultBreakStart = initialStart.plusHours(4).toLocalTime()
    val defaultBreakEnd = initialStart.plusHours(5).toLocalTime()
    var dateEpochDay by rememberSaveable(existing?.id) { mutableLongStateOf(initialStart.toLocalDate().toEpochDay()) }
    var startMinute by rememberSaveable(existing?.id) { mutableIntStateOf(initialStart.hour * 60 + initialStart.minute) }
    var endMinute by rememberSaveable(existing?.id) { mutableIntStateOf(initialEnd.hour * 60 + initialEnd.minute) }
    var includeBreak by rememberSaveable(existing?.id) { mutableStateOf(existing?.breakStartEpochMillis != null && existing.breakEndEpochMillis != null) }
    var breakStartMinute by rememberSaveable(existing?.id) {
        val time = existing?.breakStartEpochMillis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalTime() } ?: defaultBreakStart
        mutableIntStateOf(time.hour * 60 + time.minute)
    }
    var breakEndMinute by rememberSaveable(existing?.id) {
        val time = existing?.breakEndEpochMillis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalTime() } ?: defaultBreakEnd
        mutableIntStateOf(time.hour * 60 + time.minute)
    }
    var breakPaid by rememberSaveable(existing?.id) { mutableStateOf(existing?.breakPaid ?: false) }
    var error by rememberSaveable(existing?.id) { mutableStateOf<String?>(null) }
    var picker by rememberSaveable { mutableStateOf<EditorPicker?>(null) }
    var confirmDiscard by rememberSaveable { mutableStateOf(false) }
    val invalidBreakMessage = stringResource(R.string.break_validation)
    val unableSaveMessage = stringResource(R.string.shift_save_failed)

    val date = LocalDate.ofEpochDay(dateEpochDay)
    val startTime = LocalTime.of(startMinute / 60, startMinute % 60)
    val endTime = LocalTime.of(endMinute / 60, endMinute % 60)
    val breakStartTime = LocalTime.of(breakStartMinute / 60, breakStartMinute % 60)
    val breakEndTime = LocalTime.of(breakEndMinute / 60, breakEndMinute % 60)

    val snapshot = listOf(dateEpochDay, startMinute, endMinute, includeBreak, breakStartMinute, breakEndMinute, breakPaid)
    val initialSnapshot = rememberSaveable(existing?.id) {
        val originalBreakStart = existing?.breakStartEpochMillis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalTime() } ?: defaultBreakStart
        val originalBreakEnd = existing?.breakEndEpochMillis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalTime() } ?: defaultBreakEnd
        arrayListOf(
            initialStart.toLocalDate().toEpochDay(),
            initialStart.toLocalTime().toMinuteOfDay(),
            initialEnd.toLocalTime().toMinuteOfDay(),
            existing?.breakStartEpochMillis != null && existing.breakEndEpochMillis != null,
            originalBreakStart.toMinuteOfDay(),
            originalBreakEnd.toMinuteOfDay(),
            existing?.breakPaid ?: false,
        )
    }
    val dirty = snapshot != initialSnapshot
    fun requestDismiss() { if (dirty) confirmDiscard = true else dismiss() }
    BackHandler(onBack = ::requestDismiss)

    AlertDialog(
        onDismissRequest = ::requestDismiss,
        title = { Text(stringResource(if (existing == null) R.string.new_shift else R.string.edit_shift)) },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    AssistChip({ applyPreset(8, 17, 12, 13) { s, e, bs, be -> startMinute = s.toMinuteOfDay(); endMinute = e.toMinuteOfDay(); includeBreak = true; breakStartMinute = bs!!.toMinuteOfDay(); breakEndMinute = be!!.toMinuteOfDay(); breakPaid = false } }, { Text(stringResource(R.string.day)) }, Modifier.testTag("editor.preset.day"))
                    AssistChip({ applyPreset(16, 23, null, null) { s, e, _, _ -> startMinute = s.toMinuteOfDay(); endMinute = e.toMinuteOfDay(); includeBreak = false; breakPaid = false } }, { Text(stringResource(R.string.evening)) }, Modifier.testTag("editor.preset.evening"))
                    AssistChip({ applyPreset(22, 7, null, null) { s, e, _, _ -> startMinute = s.toMinuteOfDay(); endMinute = e.toMinuteOfDay(); includeBreak = false; breakPaid = false } }, { Text(stringResource(R.string.night)) }, Modifier.testTag("editor.preset.night"))
                }
                PickerRow(stringResource(R.string.date), date.format(DateTimeFormatter.ofPattern("EEE d MMM yyyy"))) { picker = EditorPicker.DATE }
                PickerRow(stringResource(R.string.starts), startTime.format(DateTimeFormatter.ofPattern("HH:mm"))) { picker = EditorPicker.START }
                PickerRow(stringResource(R.string.ends), endTime.format(DateTimeFormatter.ofPattern("HH:mm"))) { picker = EditorPicker.END }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(includeBreak, { includeBreak = it; error = null }, Modifier.testTag("editor.includeBreak"))
                    Text(stringResource(R.string.include_break))
                }
                if (includeBreak) {
                    PickerRow(stringResource(R.string.break_starts), breakStartTime.format(DateTimeFormatter.ofPattern("HH:mm"))) { picker = EditorPicker.BREAK_START }
                    PickerRow(stringResource(R.string.break_ends), breakEndTime.format(DateTimeFormatter.ofPattern("HH:mm"))) { picker = EditorPicker.BREAK_END }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(breakPaid, { breakPaid = it })
                        Spacer(Modifier.width(12.dp))
                        Text(stringResource(R.string.paid_break))
                    }
                    Text(stringResource(if (breakPaid) R.string.paid_break_help else R.string.unpaid_break_help), style = MaterialTheme.typography.bodySmall)
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            Button({
                buildShift(existing, date, startTime, endTime, includeBreak, breakStartTime, breakEndTime, breakPaid, zone)
                    .onSuccess(save)
                    .onFailure { error = if (it is IllegalArgumentException) invalidBreakMessage else unableSaveMessage }
            }, modifier = Modifier.testTag("editor.save")) { Text(stringResource(R.string.save)) }
        },
        dismissButton = { TextButton(::requestDismiss) { Text(stringResource(R.string.cancel)) } },
    )

    if (picker == EditorPicker.DATE) {
        val dateState = rememberDatePickerState(initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { picker = null },
            confirmButton = { TextButton({
                dateState.selectedDateMillis?.let { dateEpochDay = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toEpochDay() }
                picker = null
            }) { Text(stringResource(R.string.ok)) } },
            dismissButton = { TextButton({ picker = null }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(dateState) }
    }
    picker?.takeIf { it != EditorPicker.DATE }?.let { selectedPicker ->
        val initial = when (selectedPicker) {
            EditorPicker.START -> startTime
            EditorPicker.END -> endTime
            EditorPicker.BREAK_START -> breakStartTime
            EditorPicker.BREAK_END -> breakEndTime
            EditorPicker.DATE -> error("unreachable")
        }
        key(selectedPicker) {
            val timeState = rememberTimePickerState(initial.hour, initial.minute, is24Hour = true)
            AlertDialog(
                onDismissRequest = { picker = null },
                title = { Text(stringResource(R.string.select_time)) },
                text = { TimePicker(timeState) },
                confirmButton = { TextButton({
                    val selected = LocalTime.of(timeState.hour, timeState.minute)
                    when (selectedPicker) {
                        EditorPicker.START -> startMinute = selected.toMinuteOfDay()
                        EditorPicker.END -> endMinute = selected.toMinuteOfDay()
                        EditorPicker.BREAK_START -> breakStartMinute = selected.toMinuteOfDay()
                        EditorPicker.BREAK_END -> breakEndMinute = selected.toMinuteOfDay()
                        EditorPicker.DATE -> Unit
                    }
                    picker = null
                }) { Text(stringResource(R.string.ok)) } },
                dismissButton = { TextButton({ picker = null }) { Text(stringResource(R.string.cancel)) } },
            )
        }
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.discard_changes)) },
            text = { Text(stringResource(R.string.discard_message)) },
            confirmButton = { Button({ confirmDiscard = false; dismiss() }) { Text(stringResource(R.string.discard)) } },
            dismissButton = { TextButton({ confirmDiscard = false }) { Text(stringResource(R.string.keep_editing)) } },
        )
    }
}

@Composable private fun PickerRow(label: String, value: String, click: () -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
        Text(label)
        OutlinedButton(click) { Text(value) }
    }
}

private fun applyPreset(
    startHour: Int,
    endHour: Int,
    breakStartHour: Int?,
    breakEndHour: Int?,
    apply: (LocalTime, LocalTime, LocalTime?, LocalTime?) -> Unit,
) {
    apply(LocalTime.of(startHour, 0), LocalTime.of(endHour, 0), breakStartHour?.let { LocalTime.of(it, 0) }, breakEndHour?.let { LocalTime.of(it, 0) })
}

private fun buildShift(
    existing: ShiftEntity?,
    date: LocalDate,
    startTime: LocalTime,
    endTime: LocalTime,
    includeBreak: Boolean,
    breakStartTime: LocalTime,
    breakEndTime: LocalTime,
    breakPaid: Boolean,
    zone: ZoneId,
): Result<ShiftEntity> = runCatching {
    val overnight = endTime <= startTime
    val start = date.atTime(startTime).atZone(zone).toInstant()
    val end = (if (overnight) date.plusDays(1) else date).atTime(endTime).atZone(zone).toInstant()
    var breakStart: Instant? = null
    var breakEnd: Instant? = null
    if (includeBreak) {
        fun breakDate(time: LocalTime) = if (overnight && time < startTime) date.plusDays(1) else date
        val bs = breakDate(breakStartTime).atTime(breakStartTime).atZone(zone).toInstant()
        val be = breakDate(breakEndTime).atTime(breakEndTime).atZone(zone).toInstant()
        require(!bs.isBefore(start) && bs.isBefore(be) && !be.isAfter(end)) {
            "Break must be inside shift and end after it starts"
        }
        breakStart = bs
        breakEnd = be
    }
    ShiftEntity(
        id = existing?.id ?: UUID.randomUUID().toString(),
        startEpochMillis = start.toEpochMilli(),
        endEpochMillis = end.toEpochMilli(),
        breakStartEpochMillis = breakStart?.toEpochMilli(),
        breakEndEpochMillis = breakEnd?.toEpochMilli(),
        breakPaid = includeBreak && breakPaid,
        calendarEventId = existing?.calendarEventId,
        calendarSyncIdentifier = existing?.calendarSyncIdentifier,
        dominantShiftType = existing?.dominantShiftType ?: studio.magnusson.livetracker.data.ShiftType.DAY,
    )
}
