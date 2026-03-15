package com.example.honeypot

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.util.Calendar

class HoneyDatabaseHelper(context: Context) : SQLiteOpenHelper(context, "honeypot.db", null, 8) {

    override fun onCreate(db: SQLiteDatabase) {
        // Table creation if not exists
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_name TEXT,
                app_name TEXT,
                title TEXT,
                content TEXT,
                timestamp INTEGER,
                icon_byte_array BLOB,
                priority INTEGER DEFAULT 2,
                notification_id INTEGER,
                notification_tag TEXT,
                deleted INTEGER DEFAULT 0
            )
        """)
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_package ON notifications(package_name)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_timestamp ON notifications(timestamp)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_id_tag ON notifications(notification_id, notification_tag)")
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS app_cache (
                package_name TEXT PRIMARY KEY,
                description TEXT,
                timestamp INTEGER
            )
        """)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            try {
                db.execSQL("ALTER TABLE notifications ADD COLUMN app_name TEXT")
            } catch (e: Exception) {}
        }
        if (oldVersion < 3) {
            try {
                db.execSQL("ALTER TABLE notifications ADD COLUMN priority INTEGER DEFAULT 2")
            } catch (e: Exception) {}
        }
        if (oldVersion < 5) {
            try {
                db.execSQL("ALTER TABLE notifications ADD COLUMN notification_id INTEGER")
                db.execSQL("ALTER TABLE notifications ADD COLUMN notification_tag TEXT")
            } catch (e: Exception) {}
        }
        if (oldVersion < 6) {
            try {
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_package ON notifications(package_name)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_timestamp ON notifications(timestamp)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_notifications_id_tag ON notifications(notification_id, notification_tag)")
            } catch (e: Exception) {}
        }
        if (oldVersion < 7) {
            try {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS app_cache (
                        package_name TEXT PRIMARY KEY,
                        description TEXT,
                        timestamp INTEGER
                    )
                """)
            } catch (e: Exception) {}
        }
        if (oldVersion < 8) {
            try {
                db.execSQL("ALTER TABLE notifications ADD COLUMN deleted INTEGER DEFAULT 0")
            } catch (e: Exception) {}
        }
    }

    override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Keep existing user data if an older helper is accidentally shipped.
        Log.w("HoneyPot", "Database downgrade requested from $oldVersion to $newVersion. Keeping existing schema.")
    }

    fun saveNotification(packageName: String, appName: String, title: String, content: String, timestamp: Long, iconBytes: ByteArray?, priority: Int, notificationId: Int, notificationTag: String?) {
        val db = writableDatabase

        // Look for an existing row:
        // 1. Try matching by package + notificationId + notificationTag (Native Android match)
        // 2. Fallback to package + title + 60s window (Legacy/Fuzzy match)
        
        var cursor = db.rawQuery(
            """SELECT id FROM notifications 
               WHERE package_name = ? 
                 AND notification_id = ? 
                 AND COALESCE(notification_tag, '') = COALESCE(?, '')
                 AND (deleted IS NULL OR deleted = 0)
               LIMIT 1""",
            arrayOf(packageName, notificationId.toString(), notificationTag ?: "")
        )

        var existingId = if (cursor.moveToFirst()) cursor.getLong(0) else -1L
        cursor.close()

        if (existingId == -1L) {
            // Fallback for notifications that might have changed ID/Tag or historical data
            val windowMs = 60_000L
            cursor = db.rawQuery(
                """SELECT id FROM notifications
                   WHERE package_name = ?
                     AND TRIM(COALESCE(title, '')) = TRIM(COALESCE(?, ''))
                     AND timestamp >= ?
                     AND (deleted IS NULL OR deleted = 0)
                   ORDER BY timestamp DESC
                   LIMIT 1""",
                arrayOf(packageName, title, (timestamp - windowMs).toString())
            )
            existingId = if (cursor.moveToFirst()) cursor.getLong(0) else -1L
            cursor.close()
        }

        if (existingId >= 0) {
            // Update existing row with latest content, timestamp, and priority
            val values = ContentValues().apply {
                put("content", content)
                put("timestamp", timestamp)
                put("priority", priority)
                if (iconBytes != null) put("icon_byte_array", iconBytes)
            }
            db.update("notifications", values, "id = ?", arrayOf(existingId.toString()))
        } else {
            // New distinct notification — insert normally
            val values = ContentValues().apply {
                put("package_name", packageName)
                put("app_name", appName)
                put("title", title)
                put("content", content)
                put("timestamp", timestamp)
                put("icon_byte_array", iconBytes)
                put("priority", priority)
                put("notification_id", notificationId)
                put("notification_tag", notificationTag)
            }
            db.insert("notifications", null, values)
        }
        // Note: do not call db.close() — SQLiteOpenHelper manages the connection lifecycle
    }

    fun getTodayCount(): Int {
        val db = readableDatabase
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startOfToday = calendar.timeInMillis

        val cursor = db.rawQuery(
            "SELECT COUNT(*) FROM notifications WHERE timestamp >= ? AND (deleted IS NULL OR deleted = 0)",
            arrayOf(startOfToday.toString())
        )
        var count = 0
        if (cursor.moveToFirst()) count = cursor.getInt(0)
        cursor.close()
        return count
    }

    fun getTodayStats(): GradeStats {
        val db = readableDatabase
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startOfToday = calendar.timeInMillis

        var crystallized = 0
        var amber = 0
        var golden = 0
        var royal = 0

        val cursor = db.rawQuery(
            """SELECT priority, COUNT(*) FROM notifications
               WHERE timestamp >= ?
                 AND (deleted IS NULL OR deleted = 0)
               GROUP BY priority""",
            arrayOf(startOfToday.toString())
        )
        while (cursor.moveToNext()) {
            val grade = cursor.getInt(0)
            val count = cursor.getInt(1)
            when (grade) {
                0 -> crystallized = count
                1 -> amber = count
                2 -> golden = count
                3 -> royal = count
            }
        }
        cursor.close()
        return GradeStats(crystallized, amber, golden, royal)
    }
}

data class GradeStats(
    val crystallized: Int,
    val amber: Int,
    val golden: Int,
    val royal: Int
) {
    val total: Int get() = crystallized + amber + golden + royal
}
