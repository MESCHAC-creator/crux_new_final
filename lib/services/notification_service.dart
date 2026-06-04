import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

/// Manages Firebase Cloud Messaging and local notifications with CRUX branding
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  final _log = Logger();
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  NotificationService._();
  factory NotificationService() => _instance;

  /// Initialize FCM and local notifications
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request notification permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _log.i('Notifications permission denied by user');
        return;
      }

      // Get and store FCM token
      final token = await _messaging.getToken();
      _log.i('✅ FCM Token: ${token?.substring(0, 20)}...');

      // Initialize local notifications
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iOSSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iOSSettings,
      );

      await _localNotifications.initialize(initSettings);

      // Foreground messages (app is open)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Background messages
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

      // Message opened (notification tapped)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpen);

      _initialized = true;
      _log.i('✅ Notifications initialized');
    } catch (e) {
      _log.e('Notification init error: $e');
    }
  }

  /// Handle messages when app is in foreground
  void _handleForegroundMessage(RemoteMessage message) {
    _log.d('Foreground message: ${message.notification?.title}');
    _showLocalNotification(message);
  }

  /// Handle messages when app is in background/terminated
  static Future<void> _handleBackgroundMessage(RemoteMessage message) {
    Logger().d('Background message: ${message.notification?.title}');
    return Future.value();
  }

  /// Handle notification tap
  void _handleMessageOpen(RemoteMessage message) {
    _log.d('Notification tapped: ${message.data}');
    if (message.data.containsKey('meetingId')) {
      _log.i('Navigate to meeting: ${message.data['meetingId']}');
    }
  }

  /// Show local notification with CRUX styling
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'crux_notifications',
      'CRUX Notifications',
      channelDescription: 'Notifications de réunions CRUX',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      color: null,
    );

    const iOSDetails = DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails, iOS: iOSDetails),
      payload: message.data.toString(),
    );
  }

  /// Send smart notification - meeting invitation
  Future<void> notifyMeetingInvite({
    required String recipientToken,
    required String meetingName,
    required String hostName,
    required String meetingId,
  }) async {
    _log.i('📧 Meeting invite: $meetingName from $hostName');
  }

  /// Send smart notification - participant joined
  Future<void> notifyParticipantJoined({
    required String hostToken,
    required String participantName,
    required String meetingName,
  }) async {
    _log.i('👤 Participant joined: $participantName in $meetingName');
  }

  /// Send smart notification - call ended (missed call reminder)
  Future<void> notifyMissedCall({
    required String recipientToken,
    required String callerName,
  }) async {
    _log.i('📱 Missed call from $callerName');
  }

  /// Send smart notification - daily usage reminder (Duolingo-style)
  Future<void> notifyDailyReminder({
    required String userToken,
  }) async {
    _log.i('⏰ Daily reminder notification');
  }

  /// Send smart notification - pro upgrade reminder
  Future<void> notifyProUpgradeReminder({
    required String userToken,
    required int minutesRemaining,
  }) async {
    _log.i('⭐ Pro upgrade reminder: $minutesRemaining minutes left on free plan');
  }

  /// Get FCM token for user
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      _log.e('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to topic (for broadcast notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      _log.i('✅ Subscribed to topic: $topic');
    } catch (e) {
      _log.e('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _log.i('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      _log.e('Error unsubscribing from topic: $e');
    }
  }
}
