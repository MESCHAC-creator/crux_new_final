import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ══════════════════════════════════════════════════════════════════════
  // APPLICATION
  // ══════════════════════════════════════════════════════════════════════

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'crux-3c6be',
  );

  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://crux-3c6be.web.app',
  );

  static const String appVersion = '2.38.1';

  // ══════════════════════════════════════════════════════════════════════
  // LIVEKIT
  // ══════════════════════════════════════════════════════════════════════

  static const String livekitWssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
    defaultValue: 'wss://crux-88fihb12.livekit.cloud',
  );

  static const String livekitTokenServerUrl =
      'https://cloud-api.livekit.io/api/sandbox/connection-details';

  static const String livekitSandboxId = 'crux-6l6num';

  // ══════════════════════════════════════════════════════════════════════
  // TIMEOUTS
  // ══════════════════════════════════════════════════════════════════════

  static const Duration tokenTimeout =
      Duration(seconds: 30);

  static const Duration roomConnectionTimeout =
      Duration(seconds: 45);

  static const int maxReconnectAttempts = 5;

  static const Duration reconnectDelay =
      Duration(seconds: 2);

  static const Duration retryBackoff =
      Duration(seconds: 1);

  // ══════════════════════════════════════════════════════════════════════
  // MEETINGS
  // ══════════════════════════════════════════════════════════════════════

  static const int maxParticipantsStandard = 50;

  static const int maxParticipantsLarge = 1000;

  static const int livekitVisibleTileCap = 16;

  static const int freeMeetingDurationMinutes = 40;

  static bool isLargeMeeting(int? maxParticipants) {
    return (maxParticipants ?? 0) >
        maxParticipantsStandard;
  }

  // ══════════════════════════════════════════════════════════════════════
  // DEEP LINKS
  // ══════════════════════════════════════════════════════════════════════

  static const String deepLinkScheme = 'crux';

  static const String deepLinkHost = 'join';

  static String deepLink(String meetingId) {
    return '$deepLinkScheme://$deepLinkHost/$meetingId';
  }

  static String webJoinLink(String meetingId) {
    return '$appBaseUrl/join/$meetingId';
  }

  static String? parseMeetingId(String link) {
    final uri = Uri.tryParse(link.trim());

    if (uri == null) {
      return null;
    }

    // crux://join/ABC123
    if (uri.scheme == deepLinkScheme) {
      if (uri.host == deepLinkHost &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }

      return null;
    }

    // https://crux-3c6be.web.app/join/ABC123
    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[
              uri.pathSegments.length - 2
            ] ==
            'join') {
      return uri.pathSegments.last;
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // FIRESTORE
  // ══════════════════════════════════════════════════════════════════════

  static const String meetingsCollection = 'meetings';

  static const String usersCollection = 'users';

  static const String messagesCollection = 'messages';

  // ══════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ══════════════════════════════════════════════════════════════════════

  static bool get isLiveKitConfigured {
    return livekitWssUrl.startsWith('wss://') &&
        livekitSandboxId.isNotEmpty;
  }

  static String get configDiagnostics {
    return '''
LiveKit configured:
WSS: $livekitWssUrl
Sandbox: $livekitSandboxId
Token endpoint: $livekitTokenServerUrl
''';
  }

  static List<String> get livekitFallbackUrls {
    return const [];
  }
}
