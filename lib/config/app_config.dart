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

  // ── LiveKit token server (Cloud Run) ───────────────────────────────────
  static const String _tokenServerUrl = String.fromEnvironment(
    'LIVEKIT_TOKEN_SERVER_URL',
  );

  /// URL du serveur de tokens. Vide = mal configuré, à traiter côté service.
  static String get livekitTokenServerUrl => _tokenServerUrl;

  /// URLs de repli. Uniquement en debug, jamais en release.
  static const String _fallbackUrlsRaw = String.fromEnvironment(
    'LIVEKIT_FALLBACK_URLS', // ex: "http://10.0.2.2:3000,http://localhost:3000"
  );

  static List<String> get livekitFallbackUrls {
    if (!kDebugMode || _fallbackUrlsRaw.isEmpty) return const [];
    return _fallbackUrlsRaw
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList(growable: false);
  }

  /// Toutes les URLs candidates, dans l'ordre d'essai.
  static List<String> get livekitTokenUrls => [
        if (_tokenServerUrl.isNotEmpty) _tokenServerUrl,
        ...livekitFallbackUrls,
      ];

  /// Timeout de la requête HTTP vers le serveur de tokens.
  static const Duration tokenTimeout = Duration(seconds: 15);

  // ── LiveKit SFU (WSS) ──────────────────────────────────────────────────
  static const String livekitWssUrl = String.fromEnvironment(
    'LIVEKIT_WSS_URL',
  );

  /// true si l'app a tout ce qu'il faut pour rejoindre une réunion.
  static bool get isRealtimeConfigured =>
      livekitWssUrl.isNotEmpty && livekitTokenUrls.isNotEmpty;

  /// Message de diagnostic à logger au démarrage (jamais affiché à l'user).
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
  static const int tokenTtlSeconds = 86400;

  /// Durée maximale d'un appel en formule gratuite (non-PRO), en minutes.
  /// Cohérent avec l'argument marketing de ProScreen : "Fini la limite de
  /// 40 minutes en gratuit".
  static const int freeMeetingDurationMinutes = 40;

  /// Une réunion au-delà de [maxParticipantsStandard] passe en mode
  /// "large conference" (LargeConferenceScreen).
  static bool isLargeMeeting(int? maxParticipants) =>
      (maxParticipants ?? 0) > maxParticipantsStandard;

  // ── Deep links ─────────────────────────────────────────────────────────
  static const String deepLinkScheme = 'crux';
  static const String deepLinkHost = 'join';

  /// Lien natif : crux://join/<id>
  static String deepLink(String meetingId) =>
      '$deepLinkScheme://$deepLinkHost/$meetingId';

  /// Lien web universel, partageable partout : https://.../join/<id>
  static String webJoinLink(String meetingId) => '$appBaseUrl/join/$meetingId';

  /// Lien à copier / partager par défaut (web = ouvrable par tout le monde).
  static String shareLink(String meetingId) => webJoinLink(meetingId);

  /// Extrait l'ID de réunion d'un lien natif ou web. null si non reconnu.
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
    if (index != -1 && index + 1 < segments.length) return segments[index + 1];
    return segments.isNotEmpty ? segments.last : null;
  }

  // ── Firestore ──────────────────────────────────────────────────────────
  static const String meetingsCollection = 'meetings';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
}
