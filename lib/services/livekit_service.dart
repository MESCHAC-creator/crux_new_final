import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Service centralisé LiveKit pour CRUX.
///
/// Architecture Large Webinar:
///
/// - Capacité cible : 10 000 participants
/// - Vidéos rendues localement : maximum 10
/// - LiveKit SFU
/// - Adaptive Stream activé
/// - Dynacast activé
/// - Simulcast activé
///
/// IMPORTANT:
/// La capacité réelle de la room doit également être configurée
/// côté LiveKit / token server / Room Service.
///
/// Le client Flutter ne peut pas imposer à lui seul une limite
/// serveur de 10 000 participants.
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  // ===========================================================================
  // LARGE WEBINAR CONFIGURATION
  // ===========================================================================

  /// Nombre maximum de participants que CRUX prévoit pour un webinaire.
  static const int targetCapacity = 10000;

  /// Nombre maximum de vidéos affichées simultanément dans l'UI.
  ///
  /// La room peut contenir des milliers de participants, mais le client
  /// ne doit jamais essayer de rendre des milliers de vidéos.
  static const int maxVisibleVideoTiles = 10;

  /// Nombre maximum de tentatives pour obtenir un token.
  static const int maxTokenAttempts = 3;

  /// Version de l'architecture utilisée par le client.
  static const String architectureVersion =
      'large_webinar_10k_v2';

  // ===========================================================================
  // TOKEN
  // ===========================================================================

  /// Récupère un token LiveKit auprès du token server.
  ///
  /// [isHost] :
  /// - true  => host / speaker
  /// - false => audience
  ///
  /// Architecture recommandée:
  ///
  /// HOST:
  ///   canPublish   = true
  ///   canSubscribe = true
  ///
  /// AUDIENCE:
  ///   canPublish   = false
  ///   canSubscribe = true
  ///
  /// Le serveur doit impérativement recalculer ces permissions
  /// côté backend et ne jamais faire confiance aux valeurs envoyées
  /// par le client.
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final cleanRoom = room.trim();
    final cleanIdentity = identity.trim();
    final cleanName = name.trim();

    // -------------------------------------------------------------------------
    // VALIDATION
    // -------------------------------------------------------------------------

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

    final endpoint =
        AppConfig.livekitTokenEndpoint.trim();

    if (endpoint.isEmpty) {
      _error(
        'LiveKit token endpoint is empty.',
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

    // -------------------------------------------------------------------------
    // RETRY
    // -------------------------------------------------------------------------

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
          'role=${isHost ? 'speaker' : 'audience'})',
          level: 800,
        );

        final response = await http
            .post(
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(
                {
                  // ----------------------------------------------------------------
                  // Standard LiveKit token server fields
                  // ----------------------------------------------------------------

                  'room': cleanRoom,
                  'room_name': cleanRoom,

                  'identity': cleanIdentity,

                  'name': cleanName,
                  'participant_name': cleanName,

                  // ----------------------------------------------------------------
                  // CRUX role
                  // ----------------------------------------------------------------

                  'isHost': isHost,

                  'role': isHost
                      ? 'speaker'
                      : 'audience',

                  // ----------------------------------------------------------------
                  // Permissions requested by the client.
                  //
                  // IMPORTANT:
                  // The backend MUST validate/recalculate these values.
                  // ----------------------------------------------------------------

                  'canPublish': isHost,
                  'canSubscribe': true,

                  // ----------------------------------------------------------------
                  // Large webinar metadata
                  // ----------------------------------------------------------------

                  'conferenceType':
                      'large_webinar',

                  'architecture':
                      architectureVersion,

                  'targetCapacity':
                      targetCapacity,

                  'maxParticipants':
                      targetCapacity,

                  'maxVisibleVideoTiles':
                      maxVisibleVideoTiles,

                  // ----------------------------------------------------------------
                  // Optimization flags
                  // ----------------------------------------------------------------

                  'adaptiveStream': true,

                  'dynacast': true,

                  'simulcast': true,

                  // ----------------------------------------------------------------
                  // Audience / speaker behavior
                  // ----------------------------------------------------------------

                  'isAudience': !isHost,

                  'isSpeaker': isHost,
                },
              ),
            )
            .timeout(
              AppConfig.tokenTimeout,
            );

        developer.log(
          'LiveKit token response: '
          '${response.statusCode}',
          level: 800,
        );

        // ---------------------------------------------------------------------
        // HTTP ERROR
        // ---------------------------------------------------------------------

        if (response.statusCode < 200 ||
            response.statusCode >= 300) {
          _error(
            'Token server HTTP '
            '${response.statusCode}: '
            '${_safeResponseBody(response.body)}',
          );

          if (attempt < maxTokenAttempts) {
            await _waitBeforeRetry(attempt);
            continue;
          }

          return null;
        }

        // ---------------------------------------------------------------------
        // JSON
        // ---------------------------------------------------------------------

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

        // ---------------------------------------------------------------------
        // TOKEN
        // ---------------------------------------------------------------------

        final token =
            _extractToken(decoded);

        if (token == null ||
            token.isEmpty) {
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

        // ---------------------------------------------------------------------
        // SERVER URL
        // ---------------------------------------------------------------------

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
      } on http.ClientException catch (e) {
        _error(
          'LiveKit token HTTP client error: $e',
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

  /// Accepte plusieurs formats de token server.
  ///
  /// Cela permet à CRUX de fonctionner avec différents backends
  /// LiveKit sans modifier l'écran de conférence.
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

    // -------------------------------------------------------------------------
    // credentials
    // -------------------------------------------------------------------------

    final credentials =
        data['credentials'];

    if (credentials is Map) {
      candidates.addAll(
        [
          credentials['participantToken'],
          credentials['participant_token'],
          credentials['token'],
          credentials['accessToken'],
          credentials['access_token'],
        ],
      );
    }

    // -------------------------------------------------------------------------
    // data
    // -------------------------------------------------------------------------

    final dataField =
        data['data'];

    if (dataField is Map) {
      candidates.addAll(
        [
          dataField['participantToken'],
          dataField['participant_token'],
          dataField['token'],
          dataField['accessToken'],
          dataField['access_token'],
        ],
      );
    }

    // -------------------------------------------------------------------------
    // result
    // -------------------------------------------------------------------------

    final result =
        data['result'];

    if (result is Map) {
      candidates.addAll(
        [
          result['participantToken'],
          result['participant_token'],
          result['token'],
          result['accessToken'],
          result['access_token'],
        ],
      );
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
  // SERVER URL EXTRACTION
  // ===========================================================================

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

    // -------------------------------------------------------------------------
    // credentials
    // -------------------------------------------------------------------------

    final credentials =
        data['credentials'];

    if (credentials is Map) {
      candidates.addAll(
        [
          credentials['serverUrl'],
          credentials['server_url'],
          credentials['url'],
          credentials['livekitUrl'],
          credentials['livekit_url'],
        ],
      );
    }

    // -------------------------------------------------------------------------
    // data
    // -------------------------------------------------------------------------

    final dataField =
        data['data'];

    if (dataField is Map) {
      candidates.addAll(
        [
          dataField['serverUrl'],
          dataField['server_url'],
          dataField['url'],
          dataField['livekitUrl'],
          dataField['livekit_url'],
        ],
      );
    }

    // -------------------------------------------------------------------------
    // result
    // -------------------------------------------------------------------------

    final result =
        data['result'];

    if (result is Map) {
      candidates.addAll(
        [
          result['serverUrl'],
          result['server_url'],
          result['url'],
          result['livekitUrl'],
          result['livekit_url'],
        ],
      );
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
  // RETRY BACKOFF
  // ===========================================================================

  Future<void> _waitBeforeRetry(
    int attempt,
  ) async {
    final multiplier =
        attempt.clamp(1, 3);

    await Future<void>.delayed(
      AppConfig.retryBackoff *
          multiplier,
    );
  }

  // ===========================================================================
  // SAFE LOGGING
  // ===========================================================================

  /// Évite d'envoyer un body potentiellement énorme dans les logs.
  ///
  /// On ne log jamais un token complet.
  String _safeResponseBody(
    String body,
  ) {
    const maxLength = 500;

    if (body.length <= maxLength) {
      return body;
    }

    return '${body.substring(0, maxLength)}...';
  }

  // ===========================================================================
  // ARCHITECTURE INFORMATION
  // ===========================================================================

  String get architectureDescription {
    return '''
CRUX Large Webinar Architecture

Target capacity     : $targetCapacity participants
Visible videos      : $maxVisibleVideoTiles
Transport            : LiveKit SFU

Client optimization:
  Adaptive Stream    : enabled
  Dynacast           : enabled
  Simulcast          : enabled

HOST / SPEAKER:
  canPublish         : true
  canSubscribe       : true

AUDIENCE:
  canPublish         : false
  canSubscribe       : true

Architecture:
  10,000 participants
  -> LiveKit SFU
  -> selective subscription
  -> maximum 10 rendered video tiles
  -> audio remains independent from video rendering

Server requirement:
  max_participants >= $targetCapacity
''';
  }

  // ===========================================================================
  // CONFIGURATION HELPERS
  // ===========================================================================

  /// Nombre maximum de participants prévu par CRUX.
  int get maximumParticipants =>
      targetCapacity;

  /// Nombre maximum de vidéos que l'UI doit afficher.
  int get maximumVisibleVideos =>
      maxVisibleVideoTiles;

  /// Indique que le service est configuré pour un grand webinaire.
  bool get isLargeWebinar =>
      targetCapacity >= 3000;

  /// Indique que la cible 10K est activée.
  bool get supportsTenThousandParticipants =>
      targetCapacity >= 10000;

  // ===========================================================================
  // DIAGNOSTICS
  // ===========================================================================

  Map<String, dynamic>
      get diagnostics {
    return {
      'architecture':
          architectureVersion,
      'targetCapacity':
          targetCapacity,
      'maxVisibleVideoTiles':
          maxVisibleVideoTiles,
      'adaptiveStream':
          true,
      'dynacast':
          true,
      'simulcast':
          true,
      'transport':
          'LiveKit SFU',
      'largeWebinar':
          isLargeWebinar,
      'supports10K':
          supportsTenThousandParticipants,
    };
  }

  // ===========================================================================
  // LOGGING
  // ===========================================================================

  void _error(
    String message,
  ) {
    developer.log(
      'LiveKitService: $message',
      level: 1000,
    );
  }
}
