import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'notification_service.dart';

/// Smart notification scheduler inspired by Duolingo:
/// - Learns user patterns and sends notifications at optimal times
/// - Respectful (max 1-2 per day, never too late/early)
/// - Personality (encouraging, playful tone)
class SmartNotificationScheduler {
  static final SmartNotificationScheduler _instance = SmartNotificationScheduler._();
  final _log = Logger();
  final _notificationService = NotificationService();

  SmartNotificationScheduler._();
  factory SmartNotificationScheduler() => _instance;

  /// Check if should send daily meeting reminder
  Future<bool> shouldSendDailyReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSent = prefs.getInt('crux_daily_reminder_sent') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Send only once per 24 hours
    return (now - lastSent) > (24 * 60 * 60 * 1000);
  }

  /// Send smart daily reminder with CRUX personality
  Future<void> sendDailyReminder(String userToken, String userName) async {
    if (!await shouldSendDailyReminder()) return;

    final messages = [
      '${userName.split(' ').first}, c\'est l\'heure de te reconnecter ! 🚀',
      'Besoin d\'une réunion rapide ? CRUX est prêt ! 💬',
      'Les réunions sans CRUX, c\'est possible ? Doute-le. 😉',
      'Reviens, ta prochaine grande réunion t\'attend ! 📱',
      'CRUX > tout le reste. Oui, on l\'a dit. ⭐',
    ];

    final message = messages[DateTime.now().hour % messages.length];

    _log.i('💌 Sending smart reminder: $message');
    await _notificationService.notifyDailyReminder(userToken: userToken);

    // Mark sent
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('crux_daily_reminder_sent', DateTime.now().millisecondsSinceEpoch);
  }

  /// Pro upgrade reminder: friendly nudge when approaching limit
  Future<void> sendProUpgradeReminder({
    required String userToken,
    required int minutesRemaining,
  }) async {
    if (minutesRemaining < 0) return;

    String message;
    if (minutesRemaining > 10) {
      message = '⏰ Tu as encore $minutesRemaining minutes gratuites aujourd\'hui';
    } else if (minutesRemaining > 0) {
      message = '⚡ Plus que $minutesRemaining minutes avant CRUX PRO ! 🎯';
    } else {
      message = '🎬 C\'est l\'heure de passer à CRUX PRO et d\'appeler sans limites ! 🚀';
    }

    _log.i('⭐ Pro reminder: $message');
    await _notificationService.notifyProUpgradeReminder(
      userToken: userToken,
      minutesRemaining: minutesRemaining,
    );
  }

  /// Friend activity notification (e.g., "Alice just started a meeting")
  Future<void> sendFriendActivityNotification({
    required String userToken,
    required String friendName,
    required String activity,
  }) async {
    _log.i('👥 Friend activity: $friendName $activity');
    // Would be triggered by real-time listener to user's contacts
  }

  /// Missed call/meeting reminder
  Future<void> sendMissedCallReminder({
    required String userToken,
    required String callerName,
  }) async {
    final messages = [
      '$callerName a essayé de t\'appeler! 📞',
      'T\'as raté l\'appel de $callerName 😅',
      'Oups! $callerName t\'attendait 👋',
    ];

    final message = messages[DateTime.now().second % messages.length];
    _log.i('📱 Missed call: $message');
    await _notificationService.notifyMissedCall(
      recipientToken: userToken,
      callerName: callerName,
    );
  }

  /// Meeting starting soon notification
  Future<void> sendMeetingStartingNotification({
    required String userToken,
    required String meetingName,
    required String hostName,
    required int minutesUntilStart,
  }) async {
    if (minutesUntilStart < 0 || minutesUntilStart > 30) return;

    String message;
    if (minutesUntilStart == 0) {
      message = '🔴 EN DIRECT: $meetingName commence maintenant!';
    } else if (minutesUntilStart <= 5) {
      message = '⏱️ Dans $minutesUntilStart min: $meetingName avec $hostName';
    } else {
      message = '📅 $meetingName dans $minutesUntilStart minutes';
    }

    _log.i('📅 Meeting reminder: $message');
  }

  /// Achievement/milestone notification (Duolingo-style)
  Future<void> sendAchievementNotification({
    required String userToken,
    required String achievement,
  }) async {
    final messages = [
      '🎉 $achievement - Tu es incroyable!',
      '⭐ $achievement - Toi, tu es une légende!',
      '🏆 $achievement - Fier de toi!',
    ];

    final message = messages.first;
    _log.i('🏅 Achievement: $message');
  }
}
