package com.example.crux

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

        const val ACTION_SCREEN_SHARE_START = "com.example.crux.SCREEN_SHARE_START"
        const val ACTION_SCREEN_SHARE_STOP  = "com.example.crux.SCREEN_SHARE_STOP"
        const val ACTION_STOP_SCREEN_SHARE  = "com.example.crux.ACTION_STOP_SCREEN_SHARE"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SCREEN_SHARE_START -> {
                // Ensure service is foreground first, then post screen share notification
                ensureForeground()
                postScreenShareNotification()
            }
            ACTION_SCREEN_SHARE_STOP -> {
                getSystemService(NotificationManager::class.java)
                    ?.cancel(NOTIFICATION_SCREEN_ID)
                showCallNotification()
            }
            ACTION_STOP_SCREEN_SHARE -> {
                // User tapped "Stop sharing" in the notification — broadcast back to Flutter
                getSystemService(NotificationManager::class.java)
                    ?.cancel(NOTIFICATION_SCREEN_ID)
                showCallNotification()
                sendBroadcast(Intent("com.example.crux.STOP_SCREEN_SHARE_FROM_NOTIFICATION"))
            }
            else -> {
                startCallForeground()
            }
        }
        return START_STICKY
    }

    private fun startCallForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildCallNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                )
            } else {
                startForeground(NOTIFICATION_ID, buildCallNotification())
            }
        } catch (e: Exception) {
            try { startForeground(NOTIFICATION_ID, buildCallNotification()) }
            catch (e2: Exception) { stopSelf(); return }
        }
    }

    // Ensure we are already a foreground service before posting additional notifications.
    // Called before postScreenShareNotification() so Android 12+ doesn't kill the process.
    // NOTE: FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION is intentionally NOT included here
    // because Android 14+ requires passing a valid MediaProjection token with that type.
    // flutter_webrtc's own ScreenCaptureService handles the mediaProjection type with
    // the proper token obtained from the consent dialog result.
    private fun ensureForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildCallNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                )
            } else {
                startForeground(NOTIFICATION_ID, buildCallNotification())
            }
        } catch (_: Exception) {
            try { startForeground(NOTIFICATION_ID, buildCallNotification()) } catch (_: Exception) {}
        }
    }

    private fun showCallNotification() {
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, buildCallNotification())
    }

    private fun postScreenShareNotification() {
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, CallForegroundService::class.java).apply {
                action = ACTION_STOP_SCREEN_SHARE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_SCREEN_ID)
            .setContentTitle("Partage d'écran CRUX actif")
            .setContentText("Votre écran est visible par les participants")
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setColor(0xFFCC0000.toInt())
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Arrêter le partage",
                stopIntent
            )
            .build()

        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_SCREEN_ID, notification)
    }

    private fun buildCallNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Réunion CRUX en cours")
            .setContentText("Appuyez pour revenir à la réunion")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val callChannel = NotificationChannel(
                CHANNEL_ID,
                "Appels CRUX",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notification d'appel CRUX en arrière-plan"
                setShowBadge(false)
            }

            val screenChannel = NotificationChannel(
                CHANNEL_SCREEN_ID,
                "Partage d'écran CRUX",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notification active pendant le partage d'écran"
                setShowBadge(false)
            }

            getSystemService(NotificationManager::class.java)?.apply {
                createNotificationChannel(callChannel)
                createNotificationChannel(screenChannel)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_SCREEN_ID)
    }
}
