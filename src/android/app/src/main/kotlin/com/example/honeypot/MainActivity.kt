package com.example.honeypot

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings
import android.content.Intent
import android.content.ComponentName
import android.text.TextUtils

import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.honeypot/notifications"
    private var methodChannel: MethodChannel? = null

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.honeypot.NEW_NOTIFICATION") {
                methodChannel?.invokeMethod("onNotificationReceived", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationServiceEnabled" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "requestNotificationPermission" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "openNotificationApp" -> {
                    openNotificationApp()
                    result.success(true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        launchApp(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "refreshStats" -> {
                    val serviceIntent = Intent(this, HoneyNotificationService::class.java)
                    startService(serviceIntent)
                    result.success(true)
                }
                "requestPostNotificationsPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(notificationReceiver, IntentFilter("com.example.honeypot.NEW_NOTIFICATION"), RECEIVER_EXPORTED)
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {
            // Ignore if not registered
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        android.util.Log.d("HoneyPot", "Enabled Listeners: $flat")
        
        if (!TextUtils.isEmpty(flat)) {
            val names = flat.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null) {
                    android.util.Log.d("HoneyPot", "Checking Component: ${cn.packageName}")
                    if (TextUtils.equals(pkgName, cn.packageName)) {
                        android.util.Log.d("HoneyPot", "Match Found!")
                        return true
                    }
                } else if (!TextUtils.isEmpty(name) && name.contains(pkgName)) {
                    // Fallback for some OS variations that might not use standard flattening
                    android.util.Log.d("HoneyPot", "Fallback Match Found in String: $name")
                    return true
                }
            }
        }
        android.util.Log.d("HoneyPot", "No Match Found for $pkgName")
        return false
    }
    private fun openNotificationApp() {
        try {
            // Priority 1: Expand the notification shade
            val statusBarService = getSystemService(Context.STATUS_BAR_SERVICE)
            val statusBarManager = Class.forName("android.app.StatusBarManager")
            val expandMethod = statusBarManager.getMethod("expandNotificationsPanel")
            expandMethod.invoke(statusBarService)
        } catch (e: Exception) {
            android.util.Log.e("HoneyPot", "Failed to expand status bar: ${e.message}")
            try {
                // Priority 2: Try to open Notification History (Android 11+)
                val intent = Intent("android.settings.NOTIFICATION_HISTORY_SETTINGS")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e2: Exception) {
                // Priority 3: Fallback to general notification settings
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        }
    }

    private fun launchApp(packageName: String) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } else {
                android.util.Log.e("HoneyPot", "No launch intent for package: $packageName")
            }
        } catch (e: Exception) {
            android.util.Log.e("HoneyPot", "Failed to launch app $packageName: ${e.message}")
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e("HoneyPot", "Failed to open battery optimization settings: ${e.message}")
        }
    }
}
