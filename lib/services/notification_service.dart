import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Manages FCM, local notifications, and periodic engagement reminders.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  final _log = Logger();
  final _messaging = FirebaseMessaging.instance;
  final _ln = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification channel IDs
  static const _mainChannel = 'crux_notifications';
  static const _reminderChannel = 'crux_reminders';

  // SharedPrefs key for last reminder schedule
  static const _lastScheduledKey = 'crux_reminder_last_scheduled';

  NotificationService._();
  factory NotificationService() => _instance;

  // ── INIT ─────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _log.i('Notifications permission denied');
        return;
      }

      final token = await _messaging.getToken();
      _log.i('✅ FCM Token: ${token?.substring(0, 20)}...');

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iOSInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _ln.initialize(
        const InitializationSettings(android: androidInit, iOS: iOSInit),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Create notification channels
      await _createChannels();

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpen);

      _initialized = true;
      _log.i('✅ Notifications initialized');

      // Schedule engagement reminders every 3h
      await scheduleEngagementReminders();
    } catch (e) {
      _log.e('Notification init error: $e');
    }
  }

  Future<void> _createChannels() async {
    if (!Platform.isAndroid) return;
    final plugin = _ln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(const AndroidNotificationChannel(
      _mainChannel,
      'CRUX Notifications',
      description: 'Notifications de réunions et messages CRUX',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));
    await plugin?.createNotificationChannel(const AndroidNotificationChannel(
      _reminderChannel,
      'Rappels CRUX',
      description: 'Rappels périodiques pour rester connecté',
      importance: Importance.defaultImportance,
    ));
  }

  // ── PERIODIC 3H ENGAGEMENT REMINDERS ─────────

  static const List<Map<String, String>> _reminderMessages = [
    {'title': '👥 Votre équipe vous attend', 'body': 'Lancez une réunion CRUX et restez connecté avec vos collaborateurs.'},
    {'title': '🎯 Productivité au rendez-vous ?', 'body': 'Planifiez votre prochaine réunion CRUX pour rester efficace.'},
    {'title': '✨ CRUX Pro disponible', 'body': 'Réunions illimitées pour 25 000 FCFA/mois. Passez à Pro dès maintenant !'},
    {'title': '📞 Quelqu\'un veut vous joindre ?', 'body': 'Ouvrez CRUX pour voir vos réunions planifiées.'},
    {'title': '🚀 Nouveau dans CRUX', 'body': 'Tableau collaboratif, sous-titres et filtres caméra disponibles dans votre réunion.'},
    {'title': '🔒 Appels sécurisés E2E', 'body': 'Toutes vos communications sont chiffrées de bout en bout avec CRUX.'},
    {'title': '⏱️ 30 min gratuites chaque jour', 'body': 'Profitez de vos 30 minutes offertes ou passez à Pro pour des réunions illimitées.'},
    {'title': '🌍 CRUX à votre service', 'body': 'Vidéoconférence premium depuis n\'importe où dans le monde.'},
  ];

  /// Schedule 8 notifications spaced 3h apart starting from now+3h.
  /// Cancels any previously scheduled reminders first.
  Future<void> scheduleEngagementReminders() async {
    try {
      // Cancel all previous reminders (IDs 100–107)
      for (int i = 100; i < 108; i++) {
        await _ln.cancel(i);
      }

      // Only reschedule if it's been more than 2h since last schedule
      // (avoids duplicates on every cold start)
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_lastScheduledKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastTs < 2 * 3600 * 1000) {
        _log.i('ℹ️ Reminders recently scheduled, skipping');
        return;
      }
      await prefs.setInt(_lastScheduledKey, now);

      final location = tz.local;
      final baseTime = tz.TZDateTime.now(location);

      for (int i = 0; i < _reminderMessages.length; i++) {
        final msg = _reminderMessages[i % _reminderMessages.length];
        final scheduledTime = baseTime.add(Duration(hours: 3 * (i + 1)));

        await _ln.zonedSchedule(
          100 + i,
          msg['title'],
          msg['body'],
          scheduledTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _reminderChannel,
              'Rappels CRUX',
              channelDescription: 'Rappels périodiques CRUX',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: false,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'engagement_reminder',
        );

        _log.i('📅 Reminder ${i + 1} scheduled at $scheduledTime');
      }

      _log.i('✅ ${_reminderMessages.length} reminders scheduled (every 3h)');
    } catch (e) {
      _log.e('Error scheduling reminders: $e');
    }
  }

  // ── MESSAGE HANDLERS ──────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    _log.d('Foreground: ${message.notification?.title}');
    _showLocalNotification(message);
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) {
    Logger().d('Background: ${message.notification?.title}');
    return Future.value();
  }

  void _handleMessageOpen(RemoteMessage message) {
    _log.d('Opened: ${message.data}');
  }

  void _onNotificationTap(NotificationResponse response) {
    _log.d('Tapped: ${response.payload}');
  }

  // ── LOCAL NOTIFICATION ────────────────────────

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _mainChannel,
      'CRUX Notifications',
      channelDescription: 'Notifications de réunions CRUX',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _ln.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails, iOS: iOSDetails),
      payload: message.data.toString(),
    );
  }

  // ── SHOW IMMEDIATE NOTIFICATION ───────────────

  Future<void> showImmediate({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    await _ln.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _mainChannel,
          'CRUX Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ── MEETING NOTIFICATIONS ─────────────────────

  Future<void> notifyMeetingInvite({
    required String recipientToken,
    required String meetingName,
    required String hostName,
    required String meetingId,
  }) async {
    _log.i('📧 Meeting invite: $meetingName from $hostName');
    await showImmediate(
      title: '📹 Invitation de $hostName',
      body: 'Vous êtes invité à rejoindre "$meetingName"',
      payload: 'meeting:$meetingId',
      id: meetingId.hashCode,
    );
  }

  Future<void> notifyParticipantJoined({
    required String hostToken,
    required String participantName,
    required String meetingName,
  }) async {
    _log.i('👤 Joined: $participantName in $meetingName');
    await showImmediate(
      title: '👤 $participantName a rejoint',
      body: 'La réunion "$meetingName" a commencé',
      id: participantName.hashCode,
    );
  }

  Future<void> notifyMissedCall({
    required String recipientToken,
    required String callerName,
  }) async {
    _log.i('📱 Missed call: $callerName');
    await showImmediate(
      title: '📞 Appel manqué',
      body: '$callerName a essayé de vous joindre sur CRUX',
      id: callerName.hashCode,
    );
  }

  Future<void> notifyDailyReminder({required String userToken}) async {
    await showImmediate(
      title: '🌅 Bonjour ! Prêt pour votre journée ?',
      body: 'Lancez votre première réunion CRUX aujourd\'hui',
      id: 50,
    );
  }

  Future<void> notifyProUpgradeReminder({
    required String userToken,
    required int minutesRemaining,
  }) async {
    await showImmediate(
      title: '⏱️ $minutesRemaining min restantes',
      body: 'Passez à CRUX Pro pour des réunions illimitées — 25 000 FCFA/mois',
      id: 51,
    );
  }

  // ── FCM HELPERS ───────────────────────────────

  Future<String?> getToken() async {
    try { return await _messaging.getToken(); } catch (e) { return null; }
  }

  Future<void> subscribeToTopic(String topic) async {
    try { await _messaging.subscribeToTopic(topic); } catch (_) {}
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try { await _messaging.unsubscribeFromTopic(topic); } catch (_) {}
  }
}
