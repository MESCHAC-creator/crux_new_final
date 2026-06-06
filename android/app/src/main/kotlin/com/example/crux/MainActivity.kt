package com.example.crux

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val PIP_CHANNEL    = "com.example.crux/pip"
    private val SCREEN_CHANNEL = "com.example.crux/screen_share"

    private var inCall = false
    private var pipChannel: MethodChannel? = null
    private var screenChannel: MethodChannel? = null

    // Receives "Stop sharing" taps from the screen share notification
    private val stopScreenShareReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            screenChannel?.invokeMethod("stopScreenShareFromNotification", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── PiP channel ────────────────────────────────────────────────
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> result.success(enterPipMode())
                "setInCall" -> {
                    inCall = call.argument<Boolean>("inCall") ?: false
                    if (inCall) startCallService() else stopCallService()
                    result.success(true)
                }
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                else -> result.notImplemented()
            }
        }

        // ── Screen share channel ────────────────────────────────────────
        screenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
        screenChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "screenShareStarted" -> {
                    notifyScreenShareStarted()
                    result.success(true)
                }
                "screenShareStopped" -> {
                    notifyScreenShareStopped()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter("com.example.crux.STOP_SCREEN_SHARE_FROM_NOTIFICATION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopScreenShareReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopScreenShareReceiver, filter)
        }
    }

    override fun onStop() {
        super.onStop()
        try { unregisterReceiver(stopScreenShareReceiver) } catch (_: Exception) {}
    }

    private fun notifyScreenShareStarted() {
        try {
            val intent = Intent(this, CallForegroundService::class.java).apply {
                action = CallForegroundService.ACTION_SCREEN_SHARE_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) { /* ignore */ }
    }

    private fun notifyScreenShareStopped() {
        try {
            val intent = Intent(this, CallForegroundService::class.java).apply {
                action = CallForegroundService.ACTION_SCREEN_SHARE_STOP
            }
            startService(intent)
        } catch (e: Exception) { /* ignore */ }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
                true
            } catch (e: Exception) { false }
        }
        return false
    }

    private fun startCallService() {
        try {
            val intent = Intent(this, CallForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) { /* ignore */ }
    }

    private fun stopCallService() {
        try {
            stopService(Intent(this, CallForegroundService::class.java))
        } catch (e: Exception) { /* ignore */ }
    }

    override fun onUserLeaveHint() {
        if (inCall) enterPipMode()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod(
            "pipModeChanged",
            mapOf("isInPip" to isInPictureInPictureMode)
        )
    }
}
