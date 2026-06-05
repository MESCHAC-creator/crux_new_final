package com.example.crux

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val PIP_CHANNEL = "com.example.crux/pip"
    private var inCall = false
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> result.success(enterPipMode())
                "setInCall" -> {
                    inCall = call.argument<Boolean>("inCall") ?: false
                    // Start/stop foreground service
                    if (inCall) {
                        startCallService()
                    } else {
                        stopCallService()
                    }
                    result.success(true)
                }
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                else -> result.notImplemented()
            }
        }
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

    // Auto-enter PiP when user presses Home during a call
    override fun onUserLeaveHint() {
        if (inCall) enterPipMode()
    }

    // Notify Flutter when PiP mode changes
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

