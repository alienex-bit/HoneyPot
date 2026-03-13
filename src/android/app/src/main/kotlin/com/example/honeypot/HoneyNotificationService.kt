package com.example.honeypot

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.content.Intent
import android.content.pm.ServiceInfo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import androidx.core.app.NotificationCompat

class HoneyNotificationService : NotificationListenerService() {
    private lateinit var dbHelper: HoneyDatabaseHelper
    private val CHANNEL_ID = "honeypot_service_channel"
    private val NOTIFICATION_ID = 1001

    override fun onCreate() {
        super.onCreate()
        dbHelper = HoneyDatabaseHelper(applicationContext)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        updateForegroundNotification()
        return START_STICKY
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        updateForegroundNotification()
    }

    private fun updateForegroundNotification() {
        val count = try { dbHelper.getTodayCount() } catch (e: Exception) { 0 }
        val notification = createNotification(count)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "HoneyPot Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active honey capture status and daily stats"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(count: Int): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val title = when {
            count == 0 -> "Jar Waiting for Pollen 🐝"
            count < 10 -> "First Drops of Honey! 🍯"
            count < 50 -> " Hive is Buzzing! 🐝"
            else -> "Honey Jar is Overflowing! 🍯"
        }

        val text = if (count == 0) {
            "Ready to capture honey in the background..."
        } else {
            "You've captured $count drops of honey today!"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_compass) // We should replace this with a bee icon later
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true) // Don't buzz on every count update
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        
        if (packageName == applicationContext.packageName) return
        
        val pm = applicationContext.packageManager
        val appName = try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }

        val iconBytes = try {
            val drawable = pm.getApplicationIcon(packageName)
            drawableToByteArray(drawable)
        } catch (e: Exception) {
            null
        }

        // Ignore group summaries to prevent duplicates
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) {
            Log.d("HoneyPot", "Ignoring Group Summary notification: $packageName")
            return
        }

        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val timestamp = sbn.postTime
        
        // Map Android priority to Honey Grade
        val androidPriority = sbn.notification.priority
        val honeyGrade = when {
            androidPriority >= 1 -> 3 // Royal Jelly
            androidPriority == 0 -> 2 // Golden Honey
            androidPriority == -1 -> 1 // Amber Honey
            else -> 0 // Crystallized
        }

        Log.d("HoneyPot", "Saving Notification: [$appName] $title (Grade: $honeyGrade)")

        dbHelper.saveNotification(packageName, appName, title, text, timestamp, iconBytes, honeyGrade)
        
        // Update the sticky notification with new count
        updateForegroundNotification()

        val intent = Intent("com.example.honeypot.NEW_NOTIFICATION")
        sendBroadcast(intent)
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable) {
            drawable.bitmap
        } else {
            val bmp = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 80, stream)
        } else {
            @Suppress("DEPRECATION")
            bitmap.compress(Bitmap.CompressFormat.WEBP, 80, stream)
        }
        return stream.toByteArray()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        Log.d("HoneyPot", "Notification Removed: ${sbn.packageName}")
        // We could update the count here if we were deleting from the notification shade,
        // but since we only capture on POST, we only update then.
    }
}
