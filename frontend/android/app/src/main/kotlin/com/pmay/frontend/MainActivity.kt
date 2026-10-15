package com.pmay.frontend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // High-importance channel so application-update pushes show as heads-up notifications.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("pmay_updates", "Application updates", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Status updates about your PMAY application"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}