package studio.magnusson.livetracker.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

class CalendarDeviceBindingRepository(
    private val context: Context,
    private val database: LiveTrackerDatabase,
    private val preferences: AppPreferencesRepository,
) {
    suspend fun ensureCurrentDevice() = withContext(Dispatchers.IO) {
        val bindingFile = File(context.noBackupFilesDir, "calendar_device_id")
        val restoredId = preferences.preferences.first().calendarDeviceId
        val localId = bindingFile.takeIf { it.isFile }?.readText()?.takeIf { it.isNotBlank() }
        when {
            restoredId == null && localId == null -> writeNewBinding(bindingFile)
            restoredId == null && localId != null -> preferences.setCalendarDeviceId(localId)
            restoredId != null && localId == restoredId -> Unit
            else -> {
                database.shiftDao().clearCalendarLinks()
                preferences.setCalendarSyncEnabled(false)
                writeNewBinding(bindingFile)
            }
        }
    }

    private suspend fun writeNewBinding(file: File) {
        val id = UUID.randomUUID().toString()
        file.parentFile?.mkdirs()
        file.writeText(id)
        preferences.setCalendarDeviceId(id)
    }
}
