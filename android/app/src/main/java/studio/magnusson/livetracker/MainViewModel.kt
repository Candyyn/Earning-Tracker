package studio.magnusson.livetracker

import android.app.Application
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import studio.magnusson.livetracker.data.*
import studio.magnusson.livetracker.domain.EarningsCalculator
import studio.magnusson.livetracker.domain.TaxRefundCalculator
import studio.magnusson.livetracker.domain.TaxRefundForecast
import java.time.*

data class MainUiState(
    val shifts: List<ShiftEntity> = emptyList(),
    val payPeriods: List<PayPeriodEntity> = emptyList(),
    val month: YearMonth = YearMonth.now(),
    val preferences: AppPreferences = AppPreferences(),
    val now: Instant = Instant.now(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val calendarStatus: CalendarSyncStatus = CalendarSyncStatus.DISCONNECTED,
) {
}
enum class CalendarSyncStatus { DISCONNECTED, PERMISSION_REQUIRED, CONNECTED, SYNCING, FAILED }
class MainViewModel(application: Application, private val savedStateHandle: SavedStateHandle) : AndroidViewModel(application) {
    private val app = application as LiveTrackerApplication
    private val calculator = EarningsCalculator()
    private val taxCalculator = TaxRefundCalculator()
    private val shiftRepository = ShiftRepository(app.database.shiftDao(), calculator)
    private val payPeriodRepository = PayPeriodRepository(app.database)
    private val calendarRepository = CalendarSyncRepository(app.database, CalendarProviderAdapter(app), calculator)
    private val calendarDeviceBinding = CalendarDeviceBindingRepository(app, app.database, app.preferences)
    private val month = MutableStateFlow(savedStateHandle.get<String>("selected_month")?.let(YearMonth::parse) ?: YearMonth.now())
    private val error = MutableStateFlow<String?>(null)
    private val calendarStatus = MutableStateFlow(CalendarSyncStatus.DISCONNECTED)
    private var cachedShiftSource: List<ShiftEntity>? = null
    private var cachedZone: ZoneId? = null
    private val cachedMonths = mutableMapOf<YearMonth, List<ShiftEntity>>()
    init {
        viewModelScope.launch {
            runCatching { calendarDeviceBinding.ensureCurrentDevice() }
                .onFailure { error.value = friendlyMessage(it) }
            refreshCalendarStateValue()
        }
    }
    val state = combine(
        shiftRepository.shifts,
        payPeriodRepository.periods,
        month,
        app.preferences.preferences,
    ) { shifts, periods, selectedMonth, preferences ->
        MainUiState(
            shifts = shifts,
            payPeriods = periods,
            month = selectedMonth,
            preferences = preferences,
            now = Instant.now(),
            isLoading = false,
        )
    }.combine(error) { loaded, message -> loaded.copy(error = message) }
        .combine(calendarStatus) { loaded, status -> loaded.copy(calendarStatus = status) }
        .catch { cause -> emit(MainUiState(isLoading = false, error = friendlyMessage(cause))) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), MainUiState())
    fun selectedMonthShifts(s: MainUiState) = shiftsForMonth(s.shifts, s.month)
    fun monthEarnings(s: MainUiState) = earningsFor(selectedMonthShifts(s), s)
    fun dashboardEarnings(s: MainUiState): Double {
        val currentMonth = YearMonth.from(s.now.atZone(ZoneId.systemDefault()))
        return earningsFor(shiftsForMonth(s.shifts, currentMonth), s)
    }
    private fun earningsFor(shifts: List<ShiftEntity>, s: MainUiState) = shifts.sumOf { calculator.earnings(it, s.payPeriods, if (s.now in it.start..it.end) s.now else it.end) }
    fun activeShift(s: MainUiState) = s.shifts.firstOrNull { s.now >= it.start && s.now < it.end }
    fun currentType(s: MainUiState) = calculator.typeAt(s.now)
    fun currentRate(s: MainUiState): Double {
        val period = s.payPeriods.firstOrNull { it.contains(s.now) } ?: return 0.0
        return period.rate(currentType(s))
    }
    fun shiftEarnings(shift: ShiftEntity, s: MainUiState) = calculator.earnings(shift, s.payPeriods, if (s.now in shift.start..shift.end) s.now else shift.end)
    fun monthDurations(s: MainUiState): Map<ShiftType, Duration> {
        val result = ShiftType.entries.associateWith { Duration.ZERO }.toMutableMap()
        selectedMonthShifts(s).forEach { shift ->
            calculator.durationsByType(shift, if (s.now in shift.start..shift.end) s.now else shift.end)
                .forEach { (type, duration) -> result[type] = result.getValue(type).plus(duration) }
        }
        return result
    }
    private fun shiftsForMonth(shifts: List<ShiftEntity>, month: YearMonth): List<ShiftEntity> {
        val zone = ZoneId.systemDefault()
        if (cachedShiftSource !== shifts || cachedZone != zone) {
            cachedShiftSource = shifts
            cachedZone = zone
            cachedMonths.clear()
        }
        return cachedMonths.getOrPut(month) {
            shifts.filter { YearMonth.from(it.start.atZone(zone)) == month }
        }
    }
    fun taxForecast(s: MainUiState, year: Int): TaxRefundForecast? {
        val zone = ZoneId.systemDefault()
        val monthly = (1..12).mapNotNull { monthNumber ->
            val start = LocalDate.of(year, monthNumber, 1).atStartOfDay(zone).toInstant()
            val end = LocalDate.of(year, monthNumber, 1).plusMonths(1).atStartOfDay(zone).toInstant()
            val breakdown = s.shifts.filter { it.end > start && it.start < end }.fold(studio.magnusson.livetracker.domain.EarningsBreakdown()) { total, shift ->
                val clipped = shift.copy(
                    startEpochMillis = maxOf(shift.startEpochMillis, start.toEpochMilli()),
                    endEpochMillis = minOf(shift.endEpochMillis, end.toEpochMilli()),
                )
                total + calculator.breakdown(clipped, s.payPeriods)
            }
            monthNumber.takeIf { breakdown.taxableGross > 0.0 }?.let { it to breakdown }
        }.toMap()
        return taxCalculator.forecast(year, monthly)
    }
    fun previousMonth() { month.update { it.minusMonths(1) }; savedStateHandle["selected_month"] = month.value.toString() }
    fun nextMonth() { month.update { it.plusMonths(1) }; savedStateHandle["selected_month"] = month.value.toString() }
    fun updateRate(id: String, rate: Double) = runOperation { payPeriodRepository.updateRate(id, rate) }
    fun splitPeriod(id: String, start: Instant) = runOperation { payPeriodRepository.splitPeriod(id, start) }
    fun deletePeriod(id: String) = runOperation { payPeriodRepository.deletePeriod(id) }
    fun updatePeriodStart(id: String, start: Instant) = runOperation { payPeriodRepository.updateStart(id, start) }
    fun updatePeriodEnd(id: String, end: Instant) = runOperation { payPeriodRepository.updateEnd(id, end) }
    fun updatePeriodRange(id: String, start: Instant, end: Instant) = runOperation { payPeriodRepository.updateRange(id, start, end) }
    fun setShowEarned(value: Boolean) = runOperation { app.preferences.setShowEarned(value) }
    fun setHideInRecents(value: Boolean) = runOperation { app.preferences.setHideInRecents(value) }
    fun save(shift: ShiftEntity) = save(shift) { }
    fun save(shift: ShiftEntity, completion: (Boolean) -> Unit) = viewModelScope.launch {
        val localSave = runCatching { shiftRepository.save(shift) }
        if (localSave.isFailure) {
            error.value = friendlyMessage(localSave.exceptionOrNull())
            completion(false)
            return@launch
        }
        if (calendarEnabled()) {
            runCatching {
                val synced = calendarRepository.save(shift)
                shiftRepository.save(synced)
            }.onFailure {
                calendarStatus.value = CalendarSyncStatus.FAILED
                error.value = app.getString(R.string.shift_saved_calendar_failed, friendlyMessage(it))
            }
        }
        completion(true)
    }
    fun delete(shift: ShiftEntity) = runOperation {
        if (calendarEnabled()) calendarRepository.delete(shift)
        shiftRepository.delete(shift)
    }
    fun refreshCalendarState() {
        viewModelScope.launch { refreshCalendarStateValue() }
    }
    fun setCalendarPermissionResult(granted: Boolean) = runOperation {
        app.preferences.setCalendarSyncEnabled(granted)
        calendarStatus.value = if (granted) CalendarSyncStatus.CONNECTED else CalendarSyncStatus.PERMISSION_REQUIRED
        if (granted) synchronizeCalendarInternal()
    }
    fun disconnectCalendar() = runOperation {
        app.preferences.setCalendarSyncEnabled(false)
        calendarStatus.value = CalendarSyncStatus.DISCONNECTED
    }
    fun synchronizeCalendar() = runOperation { synchronizeCalendarInternal() }
    fun clearError() { error.value = null }
    private fun runOperation(block: suspend () -> Unit) = viewModelScope.launch {
        runCatching { block() }.onFailure {
            error.value = friendlyMessage(it)
            if (calendarStatus.value == CalendarSyncStatus.SYNCING) calendarStatus.value = CalendarSyncStatus.FAILED
        }
    }
    private suspend fun synchronizeCalendarInternal() {
        require(hasCalendarPermission()) { "Calendar permission is required" }
        calendarStatus.value = CalendarSyncStatus.SYNCING
        calendarRepository.synchronize()
        calendarStatus.value = CalendarSyncStatus.CONNECTED
    }
    private suspend fun calendarEnabled() = app.preferences.preferences.first().calendarSyncEnabled && hasCalendarPermission()
    private suspend fun refreshCalendarStateValue() {
        calendarStatus.value = when {
            !app.preferences.preferences.first().calendarSyncEnabled -> CalendarSyncStatus.DISCONNECTED
            !hasCalendarPermission() -> CalendarSyncStatus.PERMISSION_REQUIRED
            else -> CalendarSyncStatus.CONNECTED
        }
    }
    private fun hasCalendarPermission() =
        ContextCompat.checkSelfPermission(app, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    private fun friendlyMessage(error: Throwable?): String = when (error?.message) {
        "Shift must end after it starts" -> app.getString(R.string.shift_end_validation)
        "Break must be inside shift and end after it starts" -> app.getString(R.string.break_validation)
        "Pay period not found" -> app.getString(R.string.pay_period_unavailable)
        "New pay period must start inside an existing period" -> app.getString(R.string.period_inside_validation)
        "The final pay period cannot be deleted" -> app.getString(R.string.final_period_validation)
        "Start date must be before end date" -> app.getString(R.string.period_start_validation)
        "Start date overlaps previous pay period" -> app.getString(R.string.period_previous_overlap)
        "End date must be after start date" -> app.getString(R.string.period_end_validation)
        "End date overlaps next pay period" -> app.getString(R.string.period_next_overlap)
        "Calendar permission is required" -> app.getString(R.string.calendar_permission_required)
        "No writable calendar is available" -> app.getString(R.string.no_writable_calendar)
        "Unable to create Shifts calendar" -> app.getString(R.string.calendar_create_failed)
        "Calendar provider did not return an event ID" -> app.getString(R.string.calendar_event_id_failed)
        "Calendar provider query failed" -> app.getString(R.string.calendar_query_failed)
        null -> app.getString(R.string.operation_failed)
        else -> app.getString(R.string.operation_failed)
    }
}
