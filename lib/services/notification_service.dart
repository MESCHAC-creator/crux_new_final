import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart' as crux;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'crux_notifications';
  static const _channelName = 'CRUX Notifications';
  static const _channelDescription = 'Rappels et alertes CRUX';

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
      await _ln.initialize(initSettings);

      if (Platform.isAndroid) {
        await _ln
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      _initialized = true;
      crux.logger.i('✅ NotificationService initialized');
    } catch (e, st) {
      crux.logger.e('NotificationService.initialize error', error: e, stackTrace: st);
    }
  }

  Future<void> _show(int id, String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
      await _ln.show(id, title, body, details);
    } catch (e) {
      crux.logger.e('NotificationService._show error', error: e);
    }
  }

  Future<void> notifyDailyReminder({required String userToken, String? message}) async {
    await _show(1001, 'CRUX', message ?? "C'est l'heure de te reconnecter à CRUX ! 🚀");
  }

  Future<void> notifyProUpgradeReminder({required String userToken, required int minutesRemaining}) async {
    final message = minutesRemaining > 0
        ? '⚡ Plus que $minutesRemaining minutes avant CRUX PRO !'
        : '🎬 Passe à CRUX PRO pour des appels sans limites !';
    await _show(1002, 'CRUX PRO', message);
  }

  Future<void> notifyMissedCall({required String recipientToken, required String callerName}) async {
    await _show(1003, 'Appel manqué', '$callerName a essayé de te joindre 📞');
  }

  Future<void> scheduleEngagementReminders() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 31) {
          final hasExactAlarm = await _checkExactAlarmPermission();
          if (!hasExactAlarm) {
            crux.logger.w('Exact alarm permission not granted, using inexact scheduling');
          }
        }
      }
      for (int i = 100; i < 108; i++) {
        await _ln.cancel(i);
      }
    } catch (e) {
      crux.logger.e('Error scheduling reminders: $e');
    }
  }

  Future<bool> _checkExactAlarmPermission() async => true;
}
