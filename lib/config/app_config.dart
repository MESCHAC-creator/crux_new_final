import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ══════════════════════════════════════════════════════════════════════
  // FIREBASE / APPLICATION
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

  /// URL HTTPS du serveur qui génère les tokens LiveKit.
  ///
  /// Exemple :
  /// https://mon-backend.example.com
  static const String _tokenServerUrl = String.fromEnvironment(
    'LIVEKIT_TOKEN_SERVER_URL',
    defaultValue: 'https://crux-6l6num.sandbox.livekit.io',
  );

  /// URL WebSocket de LiveKit.
  ///
  /// Exemple :
  /// wss://xxxx.livekit.cloud
  static const String _wssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
    defaultValue: 'wss://crux-88fihb12.livekit.cloud',
  );

  static String get livekitTokenServerUrl => _normalizeUrl(
        _tokenServerUrl,
      );

  static String get livekitWssUrl => _normalizeUrl(
        _wssUrl,
      );

  // ══════════════════════════════════════════════════════════════════════
  // FALLBACK LIVEKIT
  // ══════════════════════════════════════════════════════════════════════

  static const String _fallbackUrlsRaw = String.fromEnvironment(
    'LIVEKIT_FALLBACK_URLS',
    defaultValue: '',
  );

  static List<String> get livekitFallbackUrls {
    if (_fallbackUrlsRaw.trim().isEmpty) {
      return const [];
    }

    return _fallbackUrlsRaw
        .split(',')
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .map(_normalizeUrl)
        .toList(growable: false);
  }

  static List<String> get livekitTokenUrls {
    final urls = <String>[];

    if (livekitTokenServerUrl.isNotEmpty &&
        !_isPlaceholder(livekitTokenServerUrl)) {
      urls.add(livekitTokenServerUrl);
    }

    urls.addAll(livekitFallbackUrls);

    return urls.toSet().toList(growable: false);
  }

  static bool get isLiveKitConfigured {
    final wss = livekitWssUrl;

    return wss.isNotEmpty &&
        !_isPlaceholder(wss) &&
        wss.startsWith('wss://') &&
        livekitTokenUrls.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════════════════
  // TIMEOUTS
  // ══════════════════════════════════════════════════════════════════════

  static const Duration tokenTimeout = Duration(
    seconds: 30,
  );

  static const Duration roomConnectionTimeout = Duration(
    seconds: 45,
  );

  static const int maxReconnectAttempts = 5;

  static const Duration reconnectDelay = Duration(
    seconds: 2,
  );

  static const Duration retryBackoff = Duration(
    seconds: 1,
  );

  // ══════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ══════════════════════════════════════════════════════════════════════

  static String get configDiagnostics {
    if (!isLiveKitConfigured) {
      return '''
LiveKit n'est pas correctement configuré.

LIVEKIT_TOKEN_SERVER_URL:
$livekitTokenServerUrl

LIVEKIT_WSS_URL:
$livekitWssUrl

Vérifiez les --dart-define utilisés lors du build.
''';
    }

    return '''
LiveKit configuré.

Token server:
$livekitTokenServerUrl

WebSocket:
$livekitWssUrl
''';
  }

  // ══════════════════════════════════════════════════════════════════════
  // MEETING LIMITS
  // ══════════════════════════════════════════════════════════════════════

  static const int maxParticipantsStandard = 50;

  static const int maxParticipantsLarge = 1000;

  static const int freeMeetingDurationMinutes = 40;

  static const int livekitVisibleTileCap = 16;

  static bool isLargeMeeting(int? maxParticipants) {
    return (maxParticipants ?? 0) > maxParticipantsStandard;
  }

  // ══════════════════════════════════════════════════════════════════════
  // RECONNECTION
  // ══════════════════════════════════════════════════════════════════════

  static const int maxTokenAttempts = 3;

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
    final value = link.trim();

    if (value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);

    if (uri == null) {
      return null;
    }

    // crux://join/MEETING_ID
    if (uri.scheme == deepLinkScheme) {
      if (uri.host == deepLinkHost &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }

      return null;
    }

    // https://crux-3c6be.web.app/join/MEETING_ID
    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[uri.pathSegments.length - 2] == 'join') {
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
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════

  static String _normalizeUrl(String url) {
    return url.trim().replaceFirst(RegExp(r'/$'), '');
  }

  static bool _isPlaceholder(String value) {
    final lower = value.toLowerCase();

    return lower.contains('your-') ||
        lower.contains('your_') ||
        lower.contains('example.com') ||
        lower.contains('placeholder');
  }
}
