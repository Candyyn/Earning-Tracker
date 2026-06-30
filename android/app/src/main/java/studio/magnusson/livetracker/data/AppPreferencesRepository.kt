package studio.magnusson.livetracker.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "app_preferences")

data class AppPreferences(
    val showEarned: Boolean = true,
    val hideInRecents: Boolean = false,
    val calendarSyncEnabled: Boolean = false,
    val calendarDeviceId: String? = null,
)

class AppPreferencesRepository(private val context: Context) {
    val preferences: Flow<AppPreferences> = context.dataStore.data.map { values ->
        AppPreferences(
            showEarned = values[SHOW_EARNED] ?: true,
            hideInRecents = values[HIDE_IN_RECENTS] ?: false,
            calendarSyncEnabled = values[CALENDAR_SYNC_ENABLED] ?: false,
            calendarDeviceId = values[CALENDAR_DEVICE_ID],
        )
    }

    suspend fun setShowEarned(value: Boolean) {
        context.dataStore.edit { it[SHOW_EARNED] = value }
    }

    suspend fun setHideInRecents(value: Boolean) {
        context.dataStore.edit { it[HIDE_IN_RECENTS] = value }
    }

    suspend fun setCalendarSyncEnabled(value: Boolean) {
        context.dataStore.edit { it[CALENDAR_SYNC_ENABLED] = value }
    }

    suspend fun setCalendarDeviceId(value: String) {
        context.dataStore.edit { it[CALENDAR_DEVICE_ID] = value }
    }

    private companion object {
        val SHOW_EARNED = booleanPreferencesKey("show_earned")
        val HIDE_IN_RECENTS = booleanPreferencesKey("hide_in_recents")
        val CALENDAR_SYNC_ENABLED = booleanPreferencesKey("calendar_sync_enabled")
        val CALENDAR_DEVICE_ID = stringPreferencesKey("calendar_device_id")
    }
}
