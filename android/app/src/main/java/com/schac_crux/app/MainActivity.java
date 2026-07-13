package com.schac_crux.app;

import android.app.Activity;
import android.app.PictureInPictureParams;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.Configuration;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.util.Rational;
import android.view.WindowManager;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    private static final String PIP_CHANNEL    = "com.schac_crux.app/pip";
    private static final String SCREEN_CHANNEL = "com.schac_crux.app/screen_share";
    private static final int    CAPTURE_REQUEST_CODE = 1001;

    private boolean inCall = false;
    private MethodChannel pipChannel    = null;
    private MethodChannel screenChannel = null;
    private MethodChannel.Result capturePermissionResult = null;

    private final BroadcastReceiver stopScreenShareReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (screenChannel != null) {
                screenChannel.invokeMethod("stopScreenShareFromNotification", null);
            }
        }
    };

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        pipChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PIP_CHANNEL);
        pipChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "enterPip":
                    result.success(enterPipMode());
                    break;
                case "setInCall":
                    Boolean val = call.argument("inCall");
                    inCall = val != null && val;
                    if (inCall) {
                        enableCallScreenFlags();
                        startCallService();
                    } else {
                        disableCallScreenFlags();
                        stopCallService();
                    }
                    result.success(true);
                    break;
                case "isSupported":
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O);
                    break;
                default:
                    result.notImplemented();
            }
        });

        screenChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SCREEN_CHANNEL);
        screenChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "screenShareStarted":
                    notifyScreenShareStarted();
                    result.success(true);
                    break;
                case "screenShareStopped":
                    notifyScreenShareStopped();
                    result.success(true);
                    break;
                case "requestCapturePermission":
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            capturePermissionResult = result;
                            MediaProjectionManager mgr = (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
                            startActivityForResult(mgr.createScreenCaptureIntent(), CAPTURE_REQUEST_CODE);
                        } catch (Exception e) {
                            result.error("PERMISSION_ERROR", e.getMessage(), null);
                        }
                    } else {
                        result.success(false);
                    }
                    break;
                default:
                    result.notImplemented();
            }
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter("com.schac_crux.app.STOP_SCREEN_SHARE_FROM_NOTIFICATION");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopScreenShareReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(stopScreenShareReceiver, filter);
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        try { unregisterReceiver(stopScreenShareReceiver); } catch (Exception ignored) {}
    }

    private void notifyScreenShareStarted() {
        try {
            Intent intent = new Intent(this, CallForegroundService.class);
            intent.setAction(CallForegroundService.ACTION_SCREEN_SHARE_START);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
        } catch (Exception ignored) {}
    }

    private void notifyScreenShareStopped() {
        try {
            Intent intent = new Intent(this, CallForegroundService.class);
            intent.setAction(CallForegroundService.ACTION_SCREEN_SHARE_STOP);
            startService(intent);
        } catch (Exception ignored) {}
    }

    private boolean enterPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                PictureInPictureParams params = new PictureInPictureParams.Builder()
                        .setAspectRatio(new Rational(16, 9))
                        .build();
                enterPictureInPictureMode(params);
                return true;
            } catch (Exception e) {
                return false;
            }
        }
        return false;
    }

    private void startCallService() {
        try {
            Intent intent = new Intent(this, CallForegroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
        } catch (Exception ignored) {}
    }

    /** Meet/Zoom-style: keep call visible on lock screen while in a meeting. */
    private void enableCallScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            getWindow().addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }

    private void disableCallScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false);
            setTurnScreenOn(false);
        } else {
            getWindow().clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }

    private void stopCallService() {
        try {
            stopService(new Intent(this, CallForegroundService.class));
        } catch (Exception ignored) {}
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == CAPTURE_REQUEST_CODE) {
            if (capturePermissionResult != null) {
                capturePermissionResult.success(resultCode == Activity.RESULT_OK && data != null);
                capturePermissionResult = null;
            }
        }
    }

    @Override
    public void onUserLeaveHint() {
        super.onUserLeaveHint();
        if (inCall) enterPipMode();
    }

    @Override
    public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode, Configuration newConfig) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig);
        if (pipChannel != null) {
            java.util.Map<String, Object> args = new java.util.HashMap<>();
            args.put("isInPip", isInPictureInPictureMode);
            pipChannel.invokeMethod("pipModeChanged", args);
        }
    }
}
