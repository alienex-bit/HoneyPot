package com.example.honeypot

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Calendar

class HoneyDatabaseHelper(context: Context) : SQLiteOpenHelper(context, "honeypot.db", null, 3) {

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
                priority INTEGER DEFAULT 2
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
    }

    fun saveNotification(packageName: String, appName: String, title: String, content: String, timestamp: Long, iconBytes: ByteArray?, priority: Int) {
        val db = writableDatabase

        // Look for an existing row with the same package + title posted within the last 60 seconds.
        // If found, this is a dynamically-updating notification — update it in place.
        val windowMs = 60_000L
        val cursor = db.rawQuery(
            """SELECT id FROM notifications
               WHERE package_name = ?
                 AND TRIM(COALESCE(title, '')) = TRIM(COALESCE(?, ''))
                 AND timestamp >= ?
               ORDER BY timestamp DESC
               LIMIT 1""",
            arrayOf(packageName, title, (timestamp - windowMs).toString())
        )

        val existingId = if (cursor.moveToFirst()) cursor.getLong(0) else -1L
        cursor.close()

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
        
        val cursor = db.rawQuery("SELECT COUNT(*) FROM notifications WHERE timestamp >= ?", arrayOf(startOfToday.toString()))
        var count = 0
        if (cursor.moveToFirst()) {
            count = cursor.getInt(0)
        }
        cursor.close()
        // We don't close the DB because typically SQLiteOpenHelper handles it, 
        // but for read-only we might want to keep it or just return.
        return count
    }
}
