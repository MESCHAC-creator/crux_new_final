package com.schac_crux.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val PIP_CHANNEL = "com.schac_crux.app/pip"
    private val SCREEN_CHANNEL = "com.schac_crux.app/screen_share"
    private val CAPTURE_REQUEST_CODE = 1001

    private var inCall = false
    private var pipChannel: MethodChannel? = null
    private var screenChannel: MethodChannel? = null
    private var capturePermissionResult: MethodChannel.Result? = null

    private val stopScreenShareReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            screenChannel?.invokeMethod("stopScreenShareFromNotification", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> result.success(enterPipMode())
                "setInCall" -> {
                    inCall = call.argument<Boolean>("inCall") ?: false
                    if (inCall) {
                        enableCallScreenFlags()
                        startCallService()
                    } else {
                        disableCallScreenFlags()
                        stopCallService()
                    }
                    result.success(true)
                }
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                else -> result.notImplemented()
            }
        }

        screenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
        screenChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "screenShareStarted" -> {
                    notifyScreenShareStarted()
                    result.success(true)
                }
                "screenShareStopped" -> {
                    notifyScreenShareStopped()
                    result.success(true)
                }
                "requestCapturePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            capturePermissionResult = result
                            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            startActivityForResult(mgr.createScreenCaptureIntent(), CAPTURE_REQUEST_CODE)
                        } catch (e: Exception) {
                            result.error("PERMISSION_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter("com.schac_crux.app.STOP_SCREEN_SHARE_FROM_NOTIFICATION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopScreenShareReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopScreenShareReceiver, filter)
        }
    }

    override fun onStop() {
        super.onStop()
        try {
            unregisterReceiver(stopScreenShareReceiver)
        } catch (ignored: Exception) {
        }
    }

    private fun notifyScreenShareStarted() {
        try {
            val intent = Intent(this, CallForegroundService::class.java)
            intent.action = CallForegroundService.ACTION_SCREEN_SHARE_START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (ignored: Exception) {
        }
    }

    private fun notifyScreenShareStopped() {
        try {
            val intent = Intent(this, CallForegroundService::class.java)
            intent.action = CallForegroundService.ACTION_SCREEN_SHARE_STOP
            startService(intent)
        } catch (ignored: Exception) {
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
            } catch (e: Exception) {
                false
            }
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
        } catch (ignored: Exception) {
        }
    }

    private fun enableCallScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun disableCallScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun stopCallService() {
        try {
            stopService(Intent(this, CallForegroundService::class.java))
        } catch (ignored: Exception) {
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAPTURE_REQUEST_CODE) {
            capturePermissionResult?.success(resultCode == Activity.RESULT_OK && data != null)
            capturePermissionResult = null
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (inCall) enterPipMode()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val args = HashMap<String, Any>()
        args["isInPip"] = isInPictureInPictureMode
        pipChannel?.invokeMethod("pipModeChanged", args)
    }
}
