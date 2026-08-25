import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ═══════════════════════════════════════════════════════════════════════
  // APP
  // ═══════════════════════════════════════════════════════════════════════

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'crux-3c6be',
  );

  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://crux-3c6be.web.app',
  );

  static const String appVersion = '2.38.1';

  // ═══════════════════════════════════════════════════════════════════════
  // LIVEKIT
  // ═══════════════════════════════════════════════════════════════════════

  /// LiveKit Cloud URL.
  static const String livekitWssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
    defaultValue: 'wss://crux-88fihb12.livekit.cloud',
  );

  /// LiveKit Sandbox ID.
  static const String livekitSandboxId = String.fromEnvironment(
    'LIVEKIT_SANDBOX_ID',
    defaultValue: 'crux-6l6num',
  );

  /// Sandbox connection-details endpoint.
  static const String livekitSandboxEndpoint =
      'https://cloud-api.livekit.io/api/sandbox/connection-details';

  // ═══════════════════════════════════════════════════════════════════════
  // TIMEOUTS
  // ═══════════════════════════════════════════════════════════════════════

  static const Duration tokenTimeout = Duration(seconds: 30);

  static const Duration roomConnectionTimeout =
      Duration(seconds: 45);

  static const int maxReconnectAttempts = 5;

  static const Duration reconnectDelay =
      Duration(seconds: 3);

  static const Duration retryBackoff =
      Duration(seconds: 1);

  // ═══════════════════════════════════════════════════════════════════════
  // MEETINGS
  // ═══════════════════════════════════════════════════════════════════════

  static const int maxParticipantsStandard = 50;

  static const int maxParticipantsLarge = 1000;

  static const int freeMeetingDurationMinutes = 40;

  static const int livekitVisibleTileCap = 100;

  static bool isLargeMeeting(int? maxParticipants) {
    return (maxParticipants ?? 0) > maxParticipantsStandard;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RECONNECTION
  // ═══════════════════════════════════════════════════════════════════════

  static const int maxReconnects = 5;

  // ═══════════════════════════════════════════════════════════════════════
  // DEEP LINKS
  // ═══════════════════════════════════════════════════════════════════════

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

    if (uri.scheme == deepLinkScheme) {
      final segments = uri.pathSegments;

      if (segments.isNotEmpty) {
        return segments.last;
      }

      return null;
    }

    final segments = uri.pathSegments;

    if (segments.isEmpty) {
      return null;
    }

    return segments.last;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FIRESTORE
  // ═══════════════════════════════════════════════════════════════════════

  static const String meetingsCollection = 'meetings';

  static const String usersCollection = 'users';

  static const String messagesCollection = 'messages';

  // ═══════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════

  static bool get isLiveKitConfigured {
    return livekitWssUrl.startsWith('wss://') &&
        livekitSandboxId.isNotEmpty;
  }

  static String get configDiagnostics {
    if (!isLiveKitConfigured) {
      return '''
LiveKit non configuré.

LIVEKIT_WSS_URL:
$livekitWssUrl

LIVEKIT_SANDBOX_ID:
$livekitSandboxId
''';
    }

    return '''
LiveKit OK

WSS:
$livekitWssUrl

Sandbox:
$livekitSandboxId

Endpoint:
$livekitSandboxEndpoint
''';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DEBUG
  // ═══════════════════════════════════════════════════════════════════════

  static void printDiagnostics() {
    if (!kDebugMode) {
      return;
    }

    debugPrint(configDiagnostics);
  }
}
