package studio.magnusson.livetracker

import android.os.Bundle
import android.Manifest
import android.content.Intent
import android.provider.Settings as AndroidSettings
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.LocalActivity
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.core.net.toUri
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import studio.magnusson.livetracker.data.ShiftEntity
import studio.magnusson.livetracker.domain.ForecastConfidence
import java.text.NumberFormat
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); enableEdgeToEdge(); setContent { Theme { App() } } }
}
private enum class Screen { DASHBOARD, SHIFTS, SETTINGS, TAX_REFUND }

@Composable private fun App(vm: MainViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    var screen by rememberSaveable { mutableStateOf(Screen.DASHBOARD) }
    val activity = LocalActivity.current
    DisposableEffect(state.preferences.hideInRecents, activity) {
        if (state.preferences.hideInRecents) activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { }
    }
    LifecycleResumeEffect(Unit) {
        vm.refreshCalendarState()
        onPauseOrDispose { }
    }
    if (state.isLoading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    val liveNow by rememberCurrentInstant(screen == Screen.DASHBOARD || screen == Screen.SHIFTS)
    val displayedState = state.copy(now = liveNow)
    when (screen) {
        Screen.DASHBOARD -> Dashboard(displayedState, vm, { screen = Screen.SHIFTS }, { screen = Screen.SETTINGS })
        Screen.SHIFTS -> Shifts(displayedState, vm, { screen = Screen.DASHBOARD })
        Screen.SETTINGS -> Settings(state, vm, { screen = Screen.DASHBOARD }, { screen = Screen.TAX_REFUND })
        Screen.TAX_REFUND -> TaxRefundScreen(state, vm) { screen = Screen.SETTINGS }
    }
    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = vm::clearError,
            title = { Text(stringResource(R.string.error_title)) },
            text = { Text(message) },
            confirmButton = { TextButton(vm::clearError) { Text(stringResource(R.string.ok)) } },
        )
    }
}
@Composable private fun Dashboard(state: MainUiState, vm: MainViewModel, shifts: () -> Unit, settings: () -> Unit) {
    val money = remember { currencyFormatter() }
    val type = vm.currentType(state)
    val active = vm.activeShift(state)
    val earned = vm.dashboardEarnings(state)
    val progress by animateFloatAsState((earned / 25_000.0).coerceIn(0.0, 1.0).toFloat(), label = "earnings-progress")
    val aura by animateColorAsState(lerp(typeColor(type), Color.White, progress * .18f), label = "shift-aura")
    Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(aura, lerp(aura, Color(0xff17131f), .62f), Color(0xff17131f)), radius = 700f + progress * 500f)), contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.earnings).uppercase(), color = Color.White.copy(alpha = .7f))
            Text(if (state.preferences.showEarned) money.format(earned) else "••••••", Modifier.fillMaxWidth().testTag("dashboard.earnings").basicMarquee(), style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.Bold, color = Color.White, textAlign = TextAlign.Center, maxLines = 1)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.current_rate, typeLabel(type), money.format(vm.currentRate(state))), color = Color.White.copy(alpha = .8f))
            if (active != null) Text(stringResource(if (isOnBreak(active, state.now)) R.string.on_break else R.string.shift_active), color = Color.White)
        }
        Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 48.dp), horizontalArrangement = Arrangement.spacedBy(44.dp)) {
            RoundButton(Icons.Default.CalendarMonth, stringResource(R.string.shifts), "dashboard.shifts", shifts); RoundButton(Icons.Default.Settings, stringResource(R.string.settings), "dashboard.settings", settings)
        }
    }
}
@Composable private fun RoundButton(icon: ImageVector, label: String, tag: String, action: () -> Unit) {
    FloatingActionButton(action, Modifier.testTag(tag), shape = CircleShape, containerColor = Color.White.copy(alpha = .18f)) { Icon(icon, label, tint = Color.White) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun Shifts(state: MainUiState, vm: MainViewModel, back: () -> Unit) {
    BackHandler(onBack = back)
    var editorId by rememberSaveable { mutableStateOf<String?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    var deletingShiftId by rememberSaveable { mutableStateOf<String?>(null) }
    val editor = editorId?.let { id -> state.shifts.firstOrNull { it.id == id } }
    val deletingShift = deletingShiftId?.let { id -> state.shifts.firstOrNull { it.id == id } }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val deletedMessage = stringResource(R.string.shift_deleted)
    val undoLabel = stringResource(R.string.undo)
    val totals = vm.monthDurations(state)
    val monthShifts = vm.selectedMonthShifts(state)
    var autoSyncAttempted by remember { mutableStateOf(false) }
    LaunchedEffect(state.calendarStatus) {
        if (state.calendarStatus == CalendarSyncStatus.CONNECTED && !autoSyncAttempted) {
            autoSyncAttempted = true
            vm.synchronizeCalendar()
        }
    }
    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = { TopAppBar({ Text(stringResource(R.string.shifts)) }, navigationIcon = { IconButton(back, Modifier.testTag("shifts.close")) { Icon(Icons.Default.Close, stringResource(R.string.close)) } }) },
        floatingActionButton = { FloatingActionButton({ adding = true }, Modifier.testTag("shifts.add")) { Icon(Icons.Default.Add, stringResource(R.string.add)) } },
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("shifts.list"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                IconButton(vm::previousMonth, Modifier.testTag("shifts.previousMonth")) { Icon(Icons.Default.ChevronLeft, stringResource(R.string.previous_month)) }; Text(state.month.format(DateTimeFormatter.ofPattern("MMMM yyyy"))); IconButton(vm::nextMonth, Modifier.testTag("shifts.nextMonth")) { Icon(Icons.Default.ChevronRight, stringResource(R.string.next_month)) }
            } }
            item { MonthSummary(vm.monthEarnings(state), monthShifts.size, totals, state.preferences.showEarned) }
            if (monthShifts.isEmpty()) item {
                Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.no_shifts))
                    OutlinedButton({ adding = true }) { Icon(Icons.Default.Add, null); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.add_shift)) }
                }
            }
            monthShifts.groupBy { it.start.atZone(ZoneId.systemDefault()).toLocalDate() }.forEach { (date, shifts) ->
                item("header-$date") { Text(date.format(DateTimeFormatter.ofPattern("EEEE d MMMM")), fontWeight = FontWeight.Bold) }
                items(shifts, key = { it.id }) { shift -> Card({ editorId = shift.id }, Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(shiftTypeIcon(shift.dominantShiftType), null, tint = typeColor(shift.dominantShiftType), modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.shift_time_duration, time(shift.start), time(shift.end), formatDuration(shift.workedDuration())))
                    Text(typeLabel(shift.dominantShiftType), color = typeColor(shift.dominantShiftType), style = MaterialTheme.typography.labelMedium)
                    if (shift.breakStartEpochMillis != null && shift.breakEndEpochMillis != null) {
                        Text(
                            stringResource(R.string.break_time, stringResource(if (shift.breakPaid) R.string.paid_break else R.string.break_label), time(Instant.ofEpochMilli(shift.breakStartEpochMillis)), time(Instant.ofEpochMilli(shift.breakEndEpochMillis))),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(if (state.preferences.showEarned) money(vm.shiftEarnings(shift, state)) else "••••", fontWeight = FontWeight.SemiBold)
                        IconButton({ deletingShiftId = shift.id }) { Icon(Icons.Default.Delete, stringResource(R.string.delete)) }
                    }
                }
                } }
            }
        }
    }
    if (adding || editor != null) NativeShiftEditor(editor, state.month.atDay(1), { adding = false; editorId = null }) { shift ->
        vm.save(shift) { saved -> if (saved) { adding = false; editorId = null } }
    }
    deletingShift?.let { shift ->
        AlertDialog(
            onDismissRequest = { deletingShiftId = null },
            title = { Text(stringResource(R.string.delete_shift_title)) },
            text = { Text(stringResource(R.string.delete_shift_message)) },
            confirmButton = { Button({
                deletingShiftId = null
                vm.delete(shift)
                scope.launch {
                    if (snackbar.showSnackbar(deletedMessage, undoLabel, duration = SnackbarDuration.Long) == SnackbarResult.ActionPerformed) vm.save(shift)
                }
            }) { Text(stringResource(R.string.delete)) } },
            dismissButton = { TextButton({ deletingShiftId = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable private fun Settings(state: MainUiState, vm: MainViewModel, back: () -> Unit, openTaxRefund: () -> Unit) {
    BackHandler(onBack = back)
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var editingDatesId by rememberSaveable { mutableStateOf<String?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    var deletingId by rememberSaveable { mutableStateOf<String?>(null) }
    val editing = editingId?.let { id -> state.payPeriods.firstOrNull { it.id == id } }
    val editingDates = editingDatesId?.let { id -> state.payPeriods.firstOrNull { it.id == id } }
    val deleting = deletingId?.let { id -> state.payPeriods.firstOrNull { it.id == id } }
    val context = LocalContext.current
    val calendarPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        vm.setCalendarPermissionResult(result[Manifest.permission.READ_CALENDAR] == true && result[Manifest.permission.WRITE_CALENDAR] == true)
    }
    Scaffold(topBar = { TopAppBar({ Text(stringResource(R.string.settings)) }, navigationIcon = { IconButton(back, Modifier.testTag("settings.close")) { Icon(Icons.Default.Close, stringResource(R.string.close)) } }) }) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("settings.list"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(stringResource(R.string.display), style = MaterialTheme.typography.titleMedium) }
            item { SettingSwitch(stringResource(R.string.show_earnings), state.preferences.showEarned, "settings.showEarnings", vm::setShowEarned) }
            item { SettingSwitch(stringResource(R.string.hide_recents), state.preferences.hideInRecents, "settings.hideRecents", vm::setHideInRecents) }
            item { Text(stringResource(R.string.financial_tools), style = MaterialTheme.typography.titleMedium) }
            item { OutlinedButton(openTaxRefund, Modifier.fillMaxWidth()) { Icon(Icons.Default.AccountBalance, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.tax_refund)) } }
            item { Text(stringResource(R.string.calendar), style = MaterialTheme.typography.titleMedium) }
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.calendar_sync_status, calendarStatusLabel(state.calendarStatus)), fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.calendar_explanation), style = MaterialTheme.typography.bodySmall)
                        when (state.calendarStatus) {
                            CalendarSyncStatus.DISCONNECTED -> Button({ calendarPermission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) }) { Text(stringResource(R.string.connect_calendar)) }
                            CalendarSyncStatus.PERMISSION_REQUIRED -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button({ calendarPermission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) }) { Text(stringResource(R.string.try_again)) }
                                OutlinedButton({ context.startActivity(Intent(AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())) }) { Text(stringResource(R.string.open_app_settings)) }
                            }
                            CalendarSyncStatus.CONNECTED, CalendarSyncStatus.FAILED -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(vm::synchronizeCalendar) { Text(stringResource(R.string.sync_now)) }
                                OutlinedButton(vm::disconnectCalendar) { Text(stringResource(R.string.disconnect)) }
                            }
                            CalendarSyncStatus.SYNCING -> Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.syncing)) }
                        }
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    Text(stringResource(R.string.pay_periods), style = MaterialTheme.typography.titleMedium)
                    TextButton({ adding = true }) { Icon(Icons.Default.Add, null); Text(stringResource(R.string.add)) }
                }
            }
            items(state.payPeriods.sortedByDescending { it.effectiveStartEpochMillis }, key = { it.id }) { period ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                            Text(periodRange(period), Modifier.weight(1f), fontWeight = FontWeight.Bold)
                            if (period.contains(Instant.now())) Text(stringResource(R.string.active), color = Color(0xff2e7d32), style = MaterialTheme.typography.labelMedium)
                        }
                        Text(stringResource(R.string.gross_rate, money(period.grossHourlyRate)))
                        Text(
                            stringResource(R.string.rates_primary, money(period.rate(studio.magnusson.livetracker.data.ShiftType.DAY)), money(period.rate(studio.magnusson.livetracker.data.ShiftType.EVENING)), money(period.rate(studio.magnusson.livetracker.data.ShiftType.NIGHT))),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            stringResource(R.string.rates_secondary, money(period.rate(studio.magnusson.livetracker.data.ShiftType.WEEKEND)), money(period.rate(studio.magnusson.livetracker.data.ShiftType.HOLIDAY)), money(period.rate(studio.magnusson.livetracker.data.ShiftType.HOLIDAY_MAJOR))),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        FlowRow(Modifier.align(Alignment.End)) {
                            TextButton({ editingId = period.id }) { Text(stringResource(R.string.edit)) }
                            TextButton({ editingDatesId = period.id }) { Text(stringResource(R.string.dates)) }
                            TextButton({ deletingId = period.id }, enabled = state.payPeriods.size > 1) { Text(stringResource(R.string.delete)) }
                        }
                    }
                }
            }
            item { Text(stringResource(R.string.rates_explanation), style = MaterialTheme.typography.bodySmall) }
        }
    }
    editing?.let { period -> RateDialog(period.grossHourlyRate, { editingId = null }) { vm.updateRate(period.id, it); editingId = null } }
    editingDates?.let { period -> PeriodDatesDialog(period, { editingDatesId = null }) { start, end -> vm.updatePeriodRange(period.id, start, end); editingDatesId = null } }
    if (adding) AddPeriodDialog(state.payPeriods, { adding = false }) { sourceId, start -> vm.splitPeriod(sourceId, start); adding = false }
    deleting?.let { period ->
        AlertDialog(
            onDismissRequest = { deletingId = null },
            title = { Text(stringResource(R.string.delete_period_title)) },
            text = { Text(stringResource(R.string.delete_period_message)) },
            confirmButton = { Button({ vm.deletePeriod(period.id); deletingId = null }) { Text(stringResource(R.string.delete)) } },
            dismissButton = { TextButton({ deletingId = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun PeriodDatesDialog(
    period: studio.magnusson.livetracker.data.PayPeriodEntity,
    dismiss: () -> Unit,
    save: (Instant, Instant) -> Unit,
) {
    val zone = ZoneId.systemDefault()
    val initialStart = period.effectiveStart.atZone(zone).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val initialInclusiveEnd = period.effectiveEnd.atZone(zone).toLocalDate().minusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val picker = rememberDateRangePickerState(initialSelectedStartDateMillis = initialStart, initialSelectedEndDateMillis = initialInclusiveEnd)
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(stringResource(R.string.effective_period)) },
        text = { DateRangePicker(picker, modifier = Modifier.heightIn(max = 500.dp)) },
        confirmButton = { Button({
            val start = picker.selectedStartDateMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(zone).toInstant() }
            val end = picker.selectedEndDateMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant() }
            if (start != null && end != null) save(start, end)
        }, enabled = picker.selectedStartDateMillis != null && picker.selectedEndDateMillis != null) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(dismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun TaxRefundScreen(state: MainUiState, vm: MainViewModel, back: () -> Unit) {
    BackHandler(onBack = back)
    val currentYear = LocalDate.now().year
    var year by rememberSaveable { mutableIntStateOf(currentYear - 1) }
    val forecast = remember(state.shifts, state.payPeriods, year) { vm.taxForecast(state, year) }
    Scaffold(topBar = { TopAppBar({ Text(stringResource(R.string.tax_refund)) }, navigationIcon = { IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) } }) }) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                    IconButton({ year-- }, enabled = year > currentYear - 5) { Icon(Icons.Default.ChevronLeft, stringResource(R.string.previous_year)) }
                    Text(stringResource(R.string.income_year_value, year), style = MaterialTheme.typography.titleMedium)
                    IconButton({ year++ }, enabled = year < currentYear) { Icon(Icons.Default.ChevronRight, stringResource(R.string.next_year)) }
                }
            }
            if (forecast == null) {
                item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp)) { Text(stringResource(R.string.no_tax_estimate), fontWeight = FontWeight.Bold); Text(stringResource(R.string.no_tax_estimate_help, year)) } } }
            } else {
                item {
                    ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(if (forecast.midpointBalance >= 0) R.string.possible_refund else R.string.possible_tax_due), color = if (forecast.midpointBalance >= 0) Color(0xff2e7d32) else Color(0xffef6c00), fontWeight = FontWeight.Bold)
                        Text(balanceRange(forecast.estimatedBalance), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                        Text(confidenceLabel(forecast.confidence))
                        Text(stringResource(R.string.tax_disclaimer), style = MaterialTheme.typography.bodySmall)
                    } }
                }
                item {
                    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(R.string.tracked_data), fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.months_with_shifts, forecast.trackedMonthCount))
                        Text(stringResource(R.string.gross_pay_value, moneyWhole(forecast.earnings.grossPay)))
                        Text(stringResource(R.string.vacation_pay_value, moneyWhole(forecast.earnings.vacationPay)))
                        Text(stringResource(R.string.withheld_tax_value, moneyWhole(forecast.earnings.estimatedWithheldTax)))
                        Text(stringResource(R.string.final_tax_value, currencyRange(forecast.estimatedFinalTax)))
                    } }
                }
                item {
                    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(R.string.possible_payment), fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.earliest_window, if (year + 1 == 2026) stringResource(R.string.april_2026) else stringResource(R.string.april_year, year + 1)))
                        Text(stringResource(R.string.standard_window, if (year + 1 == 2026) stringResource(R.string.june_2026) else stringResource(R.string.june_year, year + 1)))
                        Text(stringResource(R.string.payment_help), style = MaterialTheme.typography.bodySmall)
                    } }
                }
                item { Text(stringResource(R.string.tax_assumptions), style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
}

@Composable private fun SettingSwitch(label: String, checked: Boolean, tag: String, change: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) { Text(label); Switch(checked, change, Modifier.testTag(tag)) }
}

@Composable private fun RateDialog(rate: Double, dismiss: () -> Unit, save: (Double) -> Unit) {
    var value by rememberSaveable(rate) { mutableStateOf(rate.toString()) }
    val parsed = value.replace(',', '.').toDoubleOrNull()
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(stringResource(R.string.edit_gross_rate)) },
        text = { OutlinedTextField(value, { value = it }, label = { Text(stringResource(R.string.sek_per_hour)) }, isError = parsed == null || parsed < 0) },
        confirmButton = { Button({ parsed?.let(save) }, enabled = parsed != null && parsed >= 0) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(dismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun AddPeriodDialog(
    periods: List<studio.magnusson.livetracker.data.PayPeriodEntity>,
    dismiss: () -> Unit,
    save: (String, Instant) -> Unit,
) {
    val zone = ZoneId.systemDefault()
    val latestStart = periods.maxOfOrNull { it.effectiveStart.atZone(zone).toLocalDate() } ?: LocalDate.now()
    val anchor = maxOf(LocalDate.now(), latestStart)
    val initial = anchor.plusMonths(1).withDayOfMonth(1).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val dateState = rememberDatePickerState(initialSelectedDateMillis = initial)
    val start = dateState.selectedDateMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(zone).toInstant() }
    val source = start?.let { instant -> periods.firstOrNull { it.contains(instant) } }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(stringResource(R.string.add_period)) },
        text = { Column { DatePicker(dateState); Text(stringResource(R.string.new_period_hint), style = MaterialTheme.typography.bodySmall) } },
        confirmButton = { Button({ if (start != null && source != null) save(source.id, start) }, enabled = start != null && source != null && start != source.effectiveStart) { Text(stringResource(R.string.add)) } },
        dismissButton = { TextButton(dismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable private fun MonthSummary(earnings: Double, count: Int, durations: Map<studio.magnusson.livetracker.data.ShiftType, Duration>, showEarned: Boolean) {
    val total = durations.values.fold(Duration.ZERO, Duration::plus)
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(pluralStringResource(R.plurals.summary, count, if (showEarned) money(earnings) else "••••••", formatDuration(total), count), fontWeight = FontWeight.Bold)
            durations.filterValues { !it.isZero }.forEach { (type, duration) ->
                Text(stringResource(R.string.type_duration, typeLabel(type), formatDuration(duration)), color = typeColor(type), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
private fun time(i: Instant) = i.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm"))
private fun currencyFormatter() = NumberFormat.getCurrencyInstance().apply { currency = Currency.getInstance("SEK") }
private fun money(value: Double) = currencyFormatter().format(value)
private fun moneyWhole(value: Double) = currencyFormatter().apply { maximumFractionDigits = 0 }.format(value)
private fun periodRange(period: studio.magnusson.livetracker.data.PayPeriodEntity): String {
    val zone = ZoneId.systemDefault()
    val format = DateTimeFormatter.ofPattern("d MMM yyyy")
    return "${period.effectiveStart.atZone(zone).format(format)} – ${period.effectiveEnd.atZone(zone).minusNanos(1).format(format)}"
}
private fun isOnBreak(shift: ShiftEntity, now: Instant): Boolean {
    val start = shift.breakStartEpochMillis?.let(Instant::ofEpochMilli) ?: return false
    val end = shift.breakEndEpochMillis?.let(Instant::ofEpochMilli) ?: return false
    return now >= start && now < end
}
@Composable private fun confidenceLabel(confidence: ForecastConfidence) = stringResource(when (confidence) {
    ForecastConfidence.LOW -> R.string.low_confidence
    ForecastConfidence.MEDIUM -> R.string.medium_confidence
    ForecastConfidence.HIGH -> R.string.high_confidence
})
private fun currencyRange(range: ClosedFloatingPointRange<Double>) = "${moneyWhole(range.start)}–${moneyWhole(range.endInclusive)}"
@Composable private fun balanceRange(range: ClosedFloatingPointRange<Double>): String = when {
    range.endInclusive < 0 -> stringResource(R.string.tax_due_range, moneyWhole(-range.endInclusive), moneyWhole(-range.start))
    range.start >= 0 -> currencyRange(range)
    else -> stringResource(R.string.mixed_tax_range, moneyWhole(range.endInclusive))
}
@Composable private fun calendarStatusLabel(status: CalendarSyncStatus) = stringResource(when (status) {
    CalendarSyncStatus.DISCONNECTED -> R.string.not_connected
    CalendarSyncStatus.PERMISSION_REQUIRED -> R.string.permission_required
    CalendarSyncStatus.CONNECTED -> R.string.connected
    CalendarSyncStatus.SYNCING -> R.string.syncing
    CalendarSyncStatus.FAILED -> R.string.sync_failed
})
private fun formatDuration(duration: Duration): String {
    val minutes = duration.toMinutes()
    return "%d h %02d min".format(minutes / 60, minutes % 60)
}
@Composable private fun typeLabel(type: studio.magnusson.livetracker.data.ShiftType) = stringResource(when (type) {
    studio.magnusson.livetracker.data.ShiftType.DAY -> R.string.day
    studio.magnusson.livetracker.data.ShiftType.EVENING -> R.string.evening
    studio.magnusson.livetracker.data.ShiftType.NIGHT -> R.string.night
    studio.magnusson.livetracker.data.ShiftType.WEEKEND -> R.string.weekend
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY -> R.string.holiday_a
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY_MAJOR -> R.string.holiday_b
})
private fun typeColor(type: studio.magnusson.livetracker.data.ShiftType) = when (type) {
    studio.magnusson.livetracker.data.ShiftType.DAY -> Color(0xff1565c0)
    studio.magnusson.livetracker.data.ShiftType.EVENING -> Color(0xff7b1fa2)
    studio.magnusson.livetracker.data.ShiftType.NIGHT -> Color(0xff3949ab)
    studio.magnusson.livetracker.data.ShiftType.WEEKEND -> Color(0xff00897b)
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY,
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY_MAJOR -> Color(0xffc62828)
}
private fun shiftTypeIcon(type: studio.magnusson.livetracker.data.ShiftType) = when (type) {
    studio.magnusson.livetracker.data.ShiftType.DAY -> Icons.Default.LightMode
    studio.magnusson.livetracker.data.ShiftType.EVENING -> Icons.Default.WbTwilight
    studio.magnusson.livetracker.data.ShiftType.NIGHT -> Icons.Default.DarkMode
    studio.magnusson.livetracker.data.ShiftType.WEEKEND -> Icons.Default.DateRange
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY -> Icons.Default.Flag
    studio.magnusson.livetracker.data.ShiftType.HOLIDAY_MAJOR -> Icons.Default.Star
}
@Composable private fun rememberCurrentInstant(enabled: Boolean): State<Instant> = produceState(Instant.now(), enabled) {
    value = Instant.now()
    if (enabled) while (true) {
        kotlinx.coroutines.delay(1_000)
        value = Instant.now()
    }
}
@Composable private fun Theme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xffce93d8)) else lightColorScheme(primary = Color(0xff7b1fa2))
    MaterialTheme(colorScheme = colors, content = content)
}
