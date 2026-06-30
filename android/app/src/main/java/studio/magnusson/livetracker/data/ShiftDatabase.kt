package studio.magnusson.livetracker.data

import android.content.Context
import androidx.room.*
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow

@Dao
interface ShiftDao {
    @Query("SELECT * FROM shifts ORDER BY startEpochMillis")
    fun observeAll(): Flow<List<ShiftEntity>>

    @Query("SELECT * FROM shifts WHERE endEpochMillis > :start AND startEpochMillis < :end ORDER BY startEpochMillis")
    suspend fun getBetween(start: Long, end: Long): List<ShiftEntity>

    @Query("UPDATE shifts SET calendarEventId = NULL, calendarSyncIdentifier = NULL")
    suspend fun clearCalendarLinks()

    @Upsert suspend fun upsert(shift: ShiftEntity)
    @Delete suspend fun delete(shift: ShiftEntity)
}

@Dao
interface PayPeriodDao {
    @Query("SELECT * FROM pay_periods ORDER BY effectiveStartEpochMillis")
    fun observeAll(): Flow<List<PayPeriodEntity>>

    @Query("SELECT * FROM pay_periods ORDER BY effectiveStartEpochMillis")
    suspend fun getAll(): List<PayPeriodEntity>

    @Upsert suspend fun upsert(period: PayPeriodEntity)
    @Delete suspend fun delete(period: PayPeriodEntity)
}

@Database(entities = [ShiftEntity::class, PayPeriodEntity::class], version = 4, exportSchema = true)
abstract class LiveTrackerDatabase : RoomDatabase() {
    abstract fun shiftDao(): ShiftDao
    abstract fun payPeriodDao(): PayPeriodDao

    companion object {
        internal val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS `pay_periods` (
                        `id` TEXT NOT NULL,
                        `grossHourlyRate` REAL NOT NULL,
                        `effectiveStartEpochMillis` INTEGER NOT NULL,
                        `effectiveEndEpochMillis` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                """.trimIndent())
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_pay_periods_effectiveStartEpochMillis` ON `pay_periods` (`effectiveStartEpochMillis`)")
                db.execSQL(
                    "INSERT INTO `pay_periods` VALUES (?, ?, ?, ?)",
                    arrayOf<Any>("initial-pay-period", 0.0, defaultStartEpochMillis(), defaultEndEpochMillis())
                )
            }
        }

        internal val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `shifts` ADD COLUMN `dominantShiftType` TEXT NOT NULL DEFAULT 'DAY'")
            }
        }

        internal val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `shifts` ADD COLUMN `calendarSyncIdentifier` TEXT")
            }
        }

        fun create(context: Context): LiveTrackerDatabase = Room.databaseBuilder(
            context, LiveTrackerDatabase::class.java, "livetracker.db"
        ).addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4).addCallback(object : Callback() {
            override fun onCreate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "INSERT INTO `pay_periods` VALUES (?, ?, ?, ?)",
                    arrayOf<Any>("initial-pay-period", 0.0, defaultStartEpochMillis(), defaultEndEpochMillis())
                )
            }
        }).build()

        private fun defaultStartEpochMillis() = java.time.LocalDate.of(1990, 1, 1)
            .atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        private fun defaultEndEpochMillis() = java.time.LocalDate.of(2100, 1, 1)
            .atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
    }
}
