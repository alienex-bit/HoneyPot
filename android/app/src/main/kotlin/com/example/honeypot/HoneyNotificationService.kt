package com.example.honeypot

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.content.Intent
import android.content.pm.ServiceInfo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import androidx.core.app.NotificationCompat
import java.util.Locale

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
        val stats = try { dbHelper.getTodayStats() } catch (e: Exception) { GradeStats(0, 0, 0, 0) }
        val notification = createNotification(stats)

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

    private fun createNotification(stats: GradeStats): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val total = stats.total

        val title = when {
            total == 0  -> "🐝 Jar is Waiting for Pollen"
            total < 10  -> "🍯 First Drops of Honey!"
            total < 50  -> "🐝 Hive is Buzzing!"
            else        -> "🍯 Honey Jar is Overflowing!"
        }

        val collapsedText = if (total == 0) {
            "Ready to capture honey in the background..."
        } else {
            "You've captured $total drops of honey today!"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(collapsedText)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        if (total > 0) {
            val style = NotificationCompat.InboxStyle()
                // Keep this short so it stays on one line in expanded view.
                .addLine("Total today: $total drops harvested")
                .addLine(formatStatLine("👑", "Royal Jelly", stats.royal))
                .addLine(formatStatLine("✨", "Golden Honey", stats.golden))
                .addLine(formatStatLine("🍂", "Amber Honey", stats.amber))
                .addLine(formatStatLine("🪨", "Crystallized", stats.crystallized))
            builder.setStyle(style)
        } else {
            val style = NotificationCompat.BigTextStyle()
                .bigText("HoneyPot is listening in the background — ready to capture your first drop of honey! 🍯")
            builder.setStyle(style)
        }

        return builder.build()
    }

    private fun formatStatLine(icon: String, label: String, count: Int): CharSequence {
        val builder = SpannableStringBuilder()
        builder.append(icon).append(" ")

        val numberStart = builder.length
        builder.append(String.format(Locale.US, "%3d", count))
        val numberEnd = builder.length
        builder.setSpan(
            StyleSpan(Typeface.BOLD),
            numberStart,
            numberEnd,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        builder.append("  ").append(label)
        return builder
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

        Log.d("HoneyPot", "Processing Notification: [$appName] $title (Grade: $honeyGrade)")

        // Process everything in a background thread to avoid blocking the notification listener (main thread)
        Thread {
            try {
                val iconBytes = try {
                    val drawable = pm.getApplicationIcon(packageName)
                    drawableToByteArray(drawable)
                } catch (e: Exception) {
                    null
                }

                dbHelper.saveNotification(
                    packageName, 
                    appName, 
                    title, 
                    text, 
                    timestamp, 
                    iconBytes, 
                    honeyGrade,
                    sbn.id,
                    sbn.tag
                )
                
                // Update the sticky notification with new count
                updateForegroundNotification()

                val intent = Intent("com.example.honeypot.NEW_NOTIFICATION")
                sendBroadcast(intent)
                Log.d("HoneyPot", "Successfully saved and broadcasted notification: $packageName")
            } catch (e: Exception) {
                Log.e("HoneyPot", "Error processing notification in background: ${e.message}")
            }
        }.start()
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
