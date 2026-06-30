package studio.magnusson.livetracker
import android.app.Application
import studio.magnusson.livetracker.data.AppPreferencesRepository
import studio.magnusson.livetracker.data.LiveTrackerDatabase
class LiveTrackerApplication : Application() {
    val database by lazy { LiveTrackerDatabase.create(this) }
    val preferences by lazy { AppPreferencesRepository(this) }
}
