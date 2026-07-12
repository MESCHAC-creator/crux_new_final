package com.schac_crux.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "crux_call_channel"
        const val CHANNEL_SCREEN_ID = "crux_screen_share_channel"
        const val NOTIFICATION_ID = 1001
        const val NOTIFICATION_SCREEN_ID = 1002

        const val ACTION_SCREEN_SHARE_START = "com.schac_crux.app.SCREEN_SHARE_START"
        const val ACTION_SCREEN_SHARE_STOP  = "com.schac_crux.app.SCREEN_SHARE_STOP"
        const val ACTION_STOP_SCREEN_SHARE  = "com.schac_crux.app.ACTION_STOP_SCREEN_SHARE"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SCREEN_SHARE_START -> {
                ensureForeground()
                postScreenShareNotification()
            }
            ACTION_SCREEN_SHARE_STOP -> {
                getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_SCREEN_ID)
                showCallNotification()
            }
            ACTION_STOP_SCREEN_SHARE -> {
                getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_SCREEN_ID)
                showCallNotification()
                sendBroadcast(Intent("com.schac_crux.app.STOP_SCREEN_SHARE_FROM_NOTIFICATION"))
            }
            else -> {
                startCallForeground()
            }
        }
        return START_STICKY
    }

    private fun startCallForeground() {
        // We start without specific type first to avoid permission crash on Android 14+ startup
        try {
            startForeground(NOTIFICATION_ID, buildCallNotification())
        } catch (e: Exception) {
            stopSelf()
        }
    }

    private fun ensureForeground() {
        try {
            startForeground(NOTIFICATION_ID, buildCallNotification())
        } catch (_: Exception) {}
    }

    private fun showCallNotification() {
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, buildCallNotification())
    }

    private fun postScreenShareNotification() {
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, CallForegroundService::class.java).apply { action = ACTION_STOP_SCREEN_SHARE },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_SCREEN_ID)
            .setContentTitle("Partage d'écran actif")
            .setContentText("Votre écran est visible par les participants")
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Arrêter", stopIntent)
            .build()

        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_SCREEN_ID, notification)
    }

    private fun buildCallNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CRUX")
            .setContentText("Réunion en cours")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Appels", NotificationManager.IMPORTANCE_LOW))
            nm?.createNotificationChannel(NotificationChannel(CHANNEL_SCREEN_ID, "Écran", NotificationManager.IMPORTANCE_HIGH))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}
