package com.example.honeypot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("HoneyPot", "Boot Completed. Service should persist automatically as a NotificationListener.")
            // NotificationListenerService is managed by the system, 
            // but we can log that boot was detected.
        }
    }
}
