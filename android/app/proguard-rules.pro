# ProGuard rules for Firebase and WebRTC/LiveKit

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# LiveKit & WebRTC
-keep class org.livekit.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn org.livekit.**
-dontwarn org.webrtc.**

# JNI
-keep class com.schac_crux.app.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
