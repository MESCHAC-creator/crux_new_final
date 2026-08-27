import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Service centralisé pour récupérer les credentials LiveKit.
///
/// Architecture CRUX Large Conference / Webinar:
///
/// - Host / speaker:
///     canPublish = true
///     canSubscribe = true
///
/// - Audience:
///     canPublish = false
///     canSubscribe = true
///
/// Le contrôle réel de ces permissions DOIT être effectué par le serveur
/// qui signe le token LiveKit. Elles ne doivent jamais être considérées
/// comme fiables lorsqu'elles sont définies uniquement côté Flutter.
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  /// Nombre de participants visés par CRUX Large Conference.
  static const int targetCapacity = 5000;

  /// Nombre maximum de vidéos que le client affiche simultanément.
  static const int maxVisibleVideoTiles = 10;

  /// Nombre maximum de tentatives HTTP.
  static const int maxTokenAttempts = 3;

  // ===========================================================================
  // TOKEN
  // ===========================================================================

  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final cleanRoom = room.trim();
    final cleanIdentity = identity.trim();
    final cleanName = name.trim();

    if (cleanRoom.isEmpty) {
      _error('Room name is empty.');
      return null;
    }

    if (cleanIdentity.isEmpty) {
      _error('Participant identity is empty.');
      return null;
    }

    if (cleanName.isEmpty) {
      _error('Participant name is empty.');
      return null;
    }

    /*
     * IMPORTANT
     *
     * Le endpoint actuel du dépôt est le Sandbox LiveKit.
     *
     * Pour la production 5K, remplacez ce endpoint par votre propre
     * token-server HTTPS.
     *
     * Le serveur doit retourner au minimum:
     *
     * {
     *   "participantToken": "...",
     *   "serverUrl": "wss://....livekit.cloud"
     * }
     *
     * et doit appliquer les permissions:
     *
     * HOST/SPEAKER:
     *   roomJoin       = true
     *   canPublish     = true
     *   canSubscribe   = true
     *
     * AUDIENCE:
     *   roomJoin       = true
     *   canPublish     = false
     *   canSubscribe   = true
     */

    for (int attempt = 1; attempt <= maxTokenAttempts; attempt++) {
      try {
        developer.log(
          'LiveKit token request '
          '(attempt=$attempt/$maxTokenAttempts, '
          'room=$cleanRoom, '
          'identity=$cleanIdentity, '
          'host=$isHost)',
          level: 800,
        );

        final response = await http
            .post(
              Uri.parse(AppConfig.livekitSandboxEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-Sandbox-ID': AppConfig.livekitSandboxId,
                'User-Agent': 'crux-flutter/${AppConfig.appVersion}',
              },
              body: jsonEncode({
                'room_name': cleanRoom,
                'participant_name': cleanIdentity,

                // Ces champs sont utiles pour votre token-server
                // personnalisé. Le Sandbox peut simplement les ignorer.
                'identity': cleanIdentity,
                'name': cleanName,
                'isHost': isHost,

                // Configuration webinar CRUX.
                'role': isHost ? 'speaker' : 'audience',
                'canPublish': isHost,
                'canSubscribe': true,

                // Métadonnées utiles côté backend.
                'conferenceType': 'large_webinar',
                'targetCapacity': targetCapacity,
                'maxVisibleVideoTiles': maxVisibleVideoTiles,
              }),
            )
            .timeout(AppConfig.tokenTimeout);

        developer.log(
          'LiveKit token response: ${response.statusCode}',
          level: 800,
        );

        if (response.statusCode < 200 ||
            response.statusCode >= 300) {
          _error(
            'LiveKit token server HTTP ${response.statusCode}: '
            '${response.body}',
          );

          if (attempt < maxTokenAttempts) {
            await Future<void>.delayed(
              AppConfig.retryBackoff * attempt,
            );
            continue;
          }

          return null;
        }

        final dynamic decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          _error('Invalid LiveKit response format.');

          if (attempt < maxTokenAttempts) {
            await Future<void>.delayed(
              AppConfig.retryBackoff * attempt,
            );
            continue;
          }

          return null;
        }

        final String? token =
            _extractToken(decoded);

        if (token == null || token.isEmpty) {
          _error(
            'LiveKit response does not contain a participant token.',
          );

          if (attempt < maxTokenAttempts) {
            await Future<void>.delayed(
              AppConfig.retryBackoff * attempt,
            );
            continue;
          }

          return null;
        }

        final String? serverUrl =
            _extractServerUrl(decoded);

        developer.log(
          'LiveKit credentials received. '
          'serverUrl=${serverUrl ?? 'provided-by-config'}',
          level: 800,
        );

        return token;
      } on TimeoutException {
        _error(
          'LiveKit token request timed out after '
          '${AppConfig.tokenTimeout.inSeconds}s.',
        );

        if (attempt < maxTokenAttempts) {
          await Future<void>.delayed(
            AppConfig.retryBackoff * attempt,
          );
          continue;
        }

        return null;
      } on FormatException catch (e) {
        _error('Invalid LiveKit JSON response: $e');

        if (attempt < maxTokenAttempts) {
          await Future<void>.delayed(
            AppConfig.retryBackoff * attempt,
          );
          continue;
        }

        return null;
      } catch (e, stackTrace) {
        developer.log(
          'LiveKit token request failed',
          error: e,
          stackTrace: stackTrace,
          level: 1000,
        );

        if (attempt < maxTokenAttempts) {
          await Future<void>.delayed(
            AppConfig.retryBackoff * attempt,
          );
          continue;
        }

        return null;
      }
    }

    return null;
  }

  // ===========================================================================
  // TOKEN EXTRACTION
  // ===========================================================================

  String? _extractToken(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['participantToken'],
      data['participant_token'],
      data['token'],
      data['accessToken'],
      data['access_token'],
    ];

    for (final value in candidates) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  String? _extractServerUrl(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['serverUrl'],
      data['server_url'],
      data['url'],
      data['livekitUrl'],
    ];

    for (final value in candidates) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  // ===========================================================================
  // DIAGNOSTICS
  // ===========================================================================

  String get architectureDescription {
    return '''
CRUX Large Conference

Target participants : $targetCapacity+
Visible videos      : $maxVisibleVideoTiles
Transport           : LiveKit SFU
Adaptive Stream     : enabled
Dynacast            : enabled
Simulcast           : enabled
Audience publishing : disabled by token server
''';
  }

  void _error(String message) {
    developer.log(
      'LiveKitService: $message',
      level: 1000,
    );
  }
}
