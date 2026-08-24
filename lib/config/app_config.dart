import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ── Firebase ───────────────────────────────────────────────────────────
  static const String firebaseProjectId = 'crux-3c6be';
  static const String appBaseUrl = 'https://crux-3c6be.web.app';
  static const String appVersion = '2.38.1';

  // ── LiveKit Configuration ──────────────────────────────────────────────
  // EN PRODUCTION : remplacer par votre URL Cloud Run
  static const String _tokenServerUrl = String.fromEnvironment(
    'https://crux-6l6num.sandbox.livekit.io',
    defaultValue: 'https://your-cloud-run-url.cloudfunctions.net',
  );

  static const String _wssUrl = String.fromEnvironment(
    'wss://crux-88fihb12.livekit.cloud',
    defaultValue: 'wss://your-livekit-server.com',
  );

  static String get livekitTokenServerUrl => _tokenServerUrl;
  static String get livekitWssUrl => _wssUrl;

  // ── Fallback URLs (debug only) ─────────────────────────────────────────
  static const String _fallbackUrlsRaw = String.fromEnvironment(
    'LIVEKIT_FALLBACK_URLS',
    defaultValue: '',
  );

  static List<String> get livekitFallbackUrls {
    if (!kDebugMode || _fallbackUrlsRaw.isEmpty) return const [];
    return _fallbackUrlsRaw
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> get livekitTokenUrls => [
        if (_tokenServerUrl.isNotEmpty && !_tokenServerUrl.contains('your-'))
          _tokenServerUrl,
        ...livekitFallbackUrls,
      ];

  static bool get isLiveKitConfigured =>
      _wssUrl.isNotEmpty &&
      !_wssUrl.contains('your-') &&
      livekitTokenUrls.isNotEmpty;

  // ── Timeouts & Retry ───────────────────────────────────────────────────
  static const Duration tokenTimeout = Duration(seconds: 30);
  static const Duration roomConnectionTimeout = Duration(seconds: 45);
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 2);
  static const Duration retryBackoff = Duration(seconds: 1);

  // ── Diagnostics ────────────────────────────────────────────────────────
  static String get configDiagnostics {
    if (!isLiveKitConfigured) {
      return '''
⚠️  LiveKit non configuré. À faire :
1. flutter run --dart-define=LIVEKIT_TOKEN_SERVER_URL="https://your-cloud-run.cloudfunctions.net"
2. flutter run --dart-define=LIVEKIT_WSS_URL="wss://your-livekit-server.com"

Ou exporter les variables :
  export LIVEKIT_TOKEN_SERVER_URL="https://..."
  export LIVEKIT_WSS_URL="wss://..."
''';
    }
    return '✅ LiveKit OK\n  Token: $livekitTokenServerUrl\n  WSS: $livekitWssUrl';
  }

  // ── Meeting Limits ─────────────────────────────────────────────────────
  static const int maxParticipantsStandard = 50;
  static const int maxParticipantsLarge = 1000;
  static const int freeMeetingDurationMinutes = 40;

  static bool isLargeMeeting(int? maxParticipants) =>
      (maxParticipants ?? 0) > maxParticipantsStandard;

  // ── Deep Links ─────────────────────────────────────────────────────────
  static const String deepLinkScheme = 'crux';
  static const String deepLinkHost = 'join';

  static String deepLink(String meetingId) =>
      '$deepLinkScheme://$deepLinkHost/$meetingId';

  static String webJoinLink(String meetingId) => '$appBaseUrl/join/$meetingId';

  static String? parseMeetingId(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    if (uri.scheme == deepLinkScheme) {
      return uri.host.isNotEmpty ? uri.host : null;
    }
    final segments = uri.pathSegments;
    return segments.isNotEmpty ? segments.last : null;
  }

  // ── Firestore ──────────────────────────────────────────────────────────
  static const String meetingsCollection = 'meetings';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
