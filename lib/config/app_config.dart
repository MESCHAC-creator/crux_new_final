import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ===========================================================================
  // APPLICATION
  // ===========================================================================

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'crux-3c6be',
  );

  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://crux-3c6be.web.app',
  );

  static const String appVersion = '2.38.1';

  // ===========================================================================
  // LIVEKIT
  // ===========================================================================

  /// URL LiveKit Cloud de production.
  ///
  /// Ne mets pas ici le Sandbox endpoint.
  static const String livekitWssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
    defaultValue: 'wss://crux-88fihb12.livekit.cloud',
  );

  /// Endpoint de TON serveur de tokens.
  ///
  /// Exemple :
  /// https://ton-backend.example.com/api/livekit/connection-details
  static const String livekitTokenEndpoint = String.fromEnvironment(
    'LIVEKIT_TOKEN_ENDPOINT',
    defaultValue: '',
  );

  // ===========================================================================
  // WEBINAR SCALE
  // ===========================================================================

  /// Capacité cible CRUX.
  static const int webinarMinimumParticipants = 10000;

  /// Nombre maximal de vidéos affichées simultanément.
  ///
  /// IMPORTANT :
  /// ce nombre n'est PAS la capacité de la room.
  static const int maxVisibleVideoTiles = 10;

  /// Nombre maximal de speakers affichés sur la scène.
  static const int maxStageParticipants = 10;

  /// Nombre maximal de messages chargés localement.
  static const int maxLocalChatMessages = 200;

  // ===========================================================================
  // STANDARD / OTHER MODES
  // ===========================================================================

  static const int maxParticipantsStandard = 1000;

  static const int maxParticipantsLarge = 10000;
  static const int livekitVisibleTileCap = 10;

  // ===========================================================================
  // TIMEOUTS
  // ===========================================================================

  static const Duration tokenTimeout = Duration(seconds: 30);

  static const Duration roomConnectionTimeout = Duration(seconds: 45);

  static const Duration reconnectDelay = Duration(seconds: 10);

  static const int maxReconnectAttempts = 8;

  // ===========================================================================
  // FREE
  // ===========================================================================

  static const int freeMeetingDurationMinutes = 45;

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  static const String meetingsCollection = 'meetings';

  static const String usersCollection = 'users';

  static const String messagesCollection = 'messages';

  // ===========================================================================
  // LINKS
  // ===========================================================================

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
      if (uri.pathSegments.isEmpty) {
        return null;
      }

      return uri.pathSegments.last;
    }

    if (uri.pathSegments.isEmpty) {
      return null;
    }

    return uri.pathSegments.last;
  }

  // ===========================================================================
  // DIAGNOSTICS
  // ===========================================================================

  static bool get isLiveKitConfigured {
    return livekitWssUrl.startsWith('wss://') &&
        livekitTokenEndpoint.startsWith('http');
  }

  static String get configDiagnostics {
    return '''
CRUX LiveKit configuration

WSS:
$livekitWssUrl

Token endpoint:
$livekitTokenEndpoint

Webinar capacity target:
$webinarMinimumParticipants

Visible video tiles:
$maxVisibleVideoTiles
''';
  }

  static void printDiagnostics() {
    if (!kDebugMode) return;

    debugPrint(configDiagnostics);
  }
}
