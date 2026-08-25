import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ═══════════════════════════════════════════════════════════════════════
  // FIREBASE
  // ═══════════════════════════════════════════════════════════════════════

  static const String firebaseProjectId = 'crux-3c6be';

  static const String appBaseUrl =
      'https://crux-3c6be.web.app';

  static const String appVersion = '2.38.1';

  // ═══════════════════════════════════════════════════════════════════════
  // LIVEKIT
  // ═══════════════════════════════════════════════════════════════════════

  /// URL HTTP officielle du serveur sandbox LiveKit.
  ///
  /// Ce n'est PAS l'URL utilisée par Room.connect().
  /// Elle sert uniquement à demander les credentials.
  static const String livekitSandboxApi =
      'https://cloud-api.livekit.io/api/sandbox/connection-details';

  /// ID du serveur sandbox LiveKit.
  static const String livekitSandboxId = 'crux-6l6num';

  /// URL LiveKit Cloud.
  ///
  /// Elle est normalement retournée par le serveur sandbox
  /// dans le champ `serverUrl`.
  ///
  /// Cette valeur sert de fallback uniquement.
  static const String livekitWssUrl =
      'wss://crux-88fihb12.livekit.cloud';

  /// Ancien nom conservé pour compatibilité avec le reste du projet.
  static const String livekitTokenServerUrl =
      livekitSandboxApi;

  static const List<String> livekitFallbackUrls = <String>[];

  static const List<String> livekitTokenUrls = <String>[
    livekitSandboxApi,
  ];

  static bool get isLiveKitConfigured {
    return livekitSandboxApi.isNotEmpty &&
        livekitSandboxId.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TIMEOUTS & RECONNECTION
  // ═══════════════════════════════════════════════════════════════════════

  static const Duration tokenTimeout =
      Duration(seconds: 20);

  static const Duration roomConnectionTimeout =
      Duration(seconds: 45);

  static const int maxReconnectAttempts = 5;

  static const Duration reconnectDelay =
      Duration(seconds: 3);

  static const Duration retryBackoff =
      Duration(seconds: 1);

  // ═══════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════

  static String get configDiagnostics {
    if (!isLiveKitConfigured) {
      return '''
⚠️ LiveKit Sandbox non configuré.

Sandbox API:
$livekitSandboxApi

Sandbox ID:
$livekitSandboxId
''';
    }

    return '''
✅ LiveKit Sandbox configuré

Sandbox API:
$livekitSandboxApi

Sandbox ID:
$livekitSandboxId

Fallback WSS:
$livekitWssUrl
''';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MEETING LIMITS
  // ═══════════════════════════════════════════════════════════════════════

  static const int maxParticipantsStandard = 50;

  static const int maxParticipantsLarge = 1000;

  static const int freeMeetingDurationMinutes = 40;

  static const int livekitVisibleTileCap = 16;

  static bool isLargeMeeting(int? maxParticipants) {
    return (maxParticipants ?? 0) > maxParticipantsStandard;
  }

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
      if (uri.host == deepLinkHost &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }

      return null;
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

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
  // DEBUG
  // ═══════════════════════════════════════════════════════════════════════

  static void printDiagnostics() {
    if (!kDebugMode) {
      return;
    }

    debugPrint(configDiagnostics);
  }
}
