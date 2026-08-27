import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Service centralisé de connexion au token server LiveKit.
///
/// Architecture CRUX Large Conference:
///
/// - Speaker / Host:
///     canPublish     = true
///     canSubscribe   = true
///
/// - Audience:
///     canPublish     = false
///     canSubscribe   = true
///
/// IMPORTANT:
/// Les permissions envoyées au token server doivent être validées
/// côté serveur. Le client Flutter ne constitue jamais une autorité
/// de sécurité.
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  // ===========================================================================
  // LARGE CONFERENCE
  // ===========================================================================

  static const int targetCapacity = 5000;

  static const int maxVisibleVideoTiles = 10;

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

    final endpoint = AppConfig.livekitTokenEndpoint.trim();

    if (endpoint.isEmpty) {
      _error(
        'LIVEKIT_TOKEN_SERVER_URL / LIVEKIT_TOKEN_ENDPOINT is empty.',
      );
      return null;
    }

    final uri = Uri.tryParse(endpoint);

    if (uri == null || !uri.hasScheme) {
      _error(
        'Invalid LiveKit token endpoint: $endpoint',
      );
      return null;
    }

    for (
      var attempt = 1;
      attempt <= maxTokenAttempts;
      attempt++
    ) {
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
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'room_name': cleanRoom,
                'participant_name': cleanIdentity,

                'room': cleanRoom,
                'identity': cleanIdentity,
                'name': cleanName,

                'isHost': isHost,

                'role': isHost
                    ? 'speaker'
                    : 'audience',

                'canPublish': isHost,
                'canSubscribe': true,

                'conferenceType': 'large_webinar',

                'targetCapacity': targetCapacity,

                'maxVisibleVideoTiles':
                    maxVisibleVideoTiles,
              }),
            )
            .timeout(
              AppConfig.tokenTimeout,
            );

        developer.log(
          'LiveKit token response: '
          '${response.statusCode}',
          level: 800,
        );

        if (response.statusCode < 200 ||
            response.statusCode >= 300) {
          _error(
            'Token server HTTP ${response.statusCode}: '
            '${response.body}',
          );

          if (attempt < maxTokenAttempts) {
            await _waitBeforeRetry(attempt);
            continue;
          }

          return null;
        }

        final dynamic decoded =
            jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          _error(
            'Invalid LiveKit response format.',
          );

          if (attempt < maxTokenAttempts) {
            await _waitBeforeRetry(attempt);
            continue;
          }

          return null;
        }

        final token = _extractToken(decoded);

        if (token == null || token.isEmpty) {
          _error(
            'LiveKit response does not contain '
            'a participant token.',
          );

          if (attempt < maxTokenAttempts) {
            await _waitBeforeRetry(attempt);
            continue;
          }

          return null;
        }

        final serverUrl =
            _extractServerUrl(decoded);

        developer.log(
          'LiveKit credentials received. '
          'serverUrl=${serverUrl ?? AppConfig.livekitWssUrl}',
          level: 800,
        );

        return token;
      } on TimeoutException {
        _error(
          'LiveKit token request timed out '
          'after ${AppConfig.tokenTimeout.inSeconds}s.',
        );

        if (attempt < maxTokenAttempts) {
          await _waitBeforeRetry(attempt);
          continue;
        }

        return null;
      } on FormatException catch (e) {
        _error(
          'Invalid LiveKit JSON response: $e',
        );

        if (attempt < maxTokenAttempts) {
          await _waitBeforeRetry(attempt);
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
          await _waitBeforeRetry(attempt);
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

  String? _extractToken(
    Map<String, dynamic> data,
  ) {
    final candidates = <dynamic>[
      data['participantToken'],
      data['participant_token'],
      data['token'],
      data['accessToken'],
      data['access_token'],
    ];

    // Certains token servers encapsulent la réponse.
    final credentials =
        data['credentials'];

    if (credentials is Map) {
      candidates.addAll([
        credentials['participantToken'],
        credentials['participant_token'],
        credentials['token'],
        credentials['accessToken'],
        credentials['access_token'],
      ]);
    }

    final dataField = data['data'];

    if (dataField is Map) {
      candidates.addAll([
        dataField['participantToken'],
        dataField['participant_token'],
        dataField['token'],
        dataField['accessToken'],
        dataField['access_token'],
      ]);
    }

    for (final value in candidates) {
      if (value is String &&
          value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  String? _extractServerUrl(
    Map<String, dynamic> data,
  ) {
    final candidates = <dynamic>[
      data['serverUrl'],
      data['server_url'],
      data['url'],
      data['livekitUrl'],
      data['livekit_url'],
    ];

    final credentials =
        data['credentials'];

    if (credentials is Map) {
      candidates.addAll([
        credentials['serverUrl'],
        credentials['server_url'],
        credentials['url'],
        credentials['livekitUrl'],
      ]);
    }

    for (final value in candidates) {
      if (value is String &&
          value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  // ===========================================================================
  // RETRY
  // ===========================================================================

  Future<void> _waitBeforeRetry(
    int attempt,
  ) async {
    final multiplier =
        attempt.clamp(1, 3);

    await Future<void>.delayed(
      AppConfig.retryBackoff * multiplier,
    );
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

Host/Speaker:
  canPublish     = true
  canSubscribe   = true

Audience:
  canPublish     = false
  canSubscribe   = true
''';
  }

  void _error(String message) {
    developer.log(
      'LiveKitService: $message',
      level: 1000,
    );
  }
}
