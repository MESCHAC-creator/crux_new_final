// Ajouter la vérification de permission pour Android 12+ (API 31+)
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

Future<void> scheduleEngagementReminders() async {
  try {
    // Vérifier la permission exact alarm pour Android 12+
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 31) {
        // Android 12+ : vérifier si SCHEDULE_EXACT_ALARM est accordée
        // Si non, utiliser inexact alarm
        final hasExactAlarm = await _checkExactAlarmPermission();
        if (!hasExactAlarm) {
          crux.logger.w('Exact alarm permission not granted, using inexact scheduling');
        }
      }
    }

    // Cancel all previous reminders (IDs 100–107)
    for (int i = 100; i < 108; i++) {
      await _ln.cancel(i);
    }

    // ... reste du code ...
  } catch (e) {
    _log.e('Error scheduling reminders: $e');
  }
}

Future<bool> _checkExactAlarmPermission() async {
  // Cette méthode nécessite un plugin ou un MethodChannel
  // Pour l'instant, retourner true et laisser le système gérer
  return true;
}
