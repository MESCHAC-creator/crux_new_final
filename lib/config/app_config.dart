import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  // ── Firebase ───────────────────────────────────────────────────────────
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'crux-3c6be',
  );

  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://crux-3c6be.web.app',
  );

  // ── Version de l'app ───────────────────────────────────────────────────
  static const String appVersion = '2.38.1';

  // ── LiveKit token server (Cloud Run) ───────────────────────────────────
  static const String _tokenServerUrl = String.fromEnvironment(
    'LIVEKIT_TOKEN_SERVER_URL',
    defaultValue: '', // À fournir en build-time
  );

  static String get livekitTokenServerUrl => _tokenServerUrl;

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
        if (_tokenServerUrl.isNotEmpty) _tokenServerUrl,
        ...livekitFallbackUrls,
      ];

  static const Duration tokenTimeout = Duration(seconds: 15);

  // ── LiveKit SFU (WSS) ──────────────────────────────────────────────────
  static const String livekitWssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
    defaultValue: '',
  );

  static bool get isRealtimeConfigured =>
      livekitWssUrl.isNotEmpty && livekitTokenUrls.isNotEmpty;

  static String get configDiagnostics {
    final missing = <String>[
      if (livekitWssUrl.isEmpty) 'LIVEKIT_WSS_URL',
      if (livekitTokenUrls.isEmpty) 'LIVEKIT_TOKEN_SERVER_URL',
    ];
    return missing.isEmpty
        ? 'AppConfig OK (project=$firebaseProjectId)'
        : 'AppConfig incomplet — dart-define manquants : ${missing.join(', ')}';
  }

  // ── Paiement (PayDunya) ────────────────────────────────────────────────
  static String get paymentSuccessUrl => '$appBaseUrl/payment-success';
  static String get paymentCancelUrl => '$appBaseUrl/payment-cancel';

  // ── Limites ────────────────────────────────────────────────────────────
  static const int maxParticipantsStandard = 50;
  static const int maxParticipantsLarge = 1000;
  static const int tokenTtlSeconds = 3600;
  static const int freeMeetingDurationMinutes = 40;

  static const Duration roomConnectionTimeout = Duration(seconds: 20);
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int livekitVisibleTileCap = 50;

  static bool isLargeMeeting(int? maxParticipants) =>
      (maxParticipants ?? 0) > maxParticipantsStandard;

  // ── Deep links ─────────────────────────────────────────────────────────
  static const String deepLinkScheme = 'crux';
  static const String deepLinkHost = 'join';

  static String deepLink(String meetingId) =>
      '$deepLinkScheme://$deepLinkHost/$meetingId';

  static String webJoinLink(String meetingId) => '$appBaseUrl/join/$meetingId';

  static String shareLink(String meetingId) => webJoinLink(meetingId);

  static String? parseMeetingId(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    if (uri.scheme == deepLinkScheme) {
      if (uri.host == deepLinkHost && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return uri.host.isNotEmpty ? uri.host : null;
    }
    final segments = uri.pathSegments;
    final index = segments.indexOf(deepLinkHost);
    if (index != -1 && index + 1 < segments.length) {
      return segments[index + 1];
    }
    return segments.isNotEmpty ? segments.last : null;
  }

  // ── Firestore ──────────────────────────────────────────────────────────
  static const String meetingsCollection = 'meetings';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
