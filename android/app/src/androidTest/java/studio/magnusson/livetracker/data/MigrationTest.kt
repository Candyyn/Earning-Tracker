package studio.magnusson.livetracker.data

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MigrationTest {
    private val name = "migration-test"
    @get:Rule val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        LiveTrackerDatabase::class.java,
    )

    @Test fun migrate3To4PreservesShiftAndAddsSyncIdentifier() {
        helper.createDatabase(name, 3).apply {
            execSQL("INSERT INTO shifts (id,startEpochMillis,endEpochMillis,breakPaid,dominantShiftType) VALUES ('shift',1000,2000,0,'DAY')")
            close()
        }
        helper.runMigrationsAndValidate(name, 4, true, LiveTrackerDatabase.MIGRATION_3_4).use { db ->
            db.query("SELECT id, calendarSyncIdentifier FROM shifts").use { cursor ->
                cursor.moveToFirst()
                assertEquals("shift", cursor.getString(0))
                assertEquals(null, cursor.getString(1))
            }
        }
    }

    @Test fun migrate2To4PreservesShiftAndAddsBothNewColumns() {
        helper.createDatabase(name, 2).apply {
            execSQL("INSERT INTO shifts (id,startEpochMillis,endEpochMillis,breakPaid) VALUES ('shift',1000,2000,0)")
            close()
        }
        helper.runMigrationsAndValidate(name, 4, true, LiveTrackerDatabase.MIGRATION_2_3, LiveTrackerDatabase.MIGRATION_3_4).use { db ->
            db.query("SELECT dominantShiftType, calendarSyncIdentifier FROM shifts").use { cursor ->
                cursor.moveToFirst()
                assertEquals("DAY", cursor.getString(0))
                assertEquals(null, cursor.getString(1))
            }
        }
    }
}
