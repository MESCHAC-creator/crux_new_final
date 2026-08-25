import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// LiveKitService
///
/// Utilise le Development/Sandbox Token Server de LiveKit.
///
/// Requête:
///
/// POST https://cloud-api.livekit.io/api/sandbox/connection-details
///
/// Headers:
/// X-Sandbox-ID: crux-6l6num
/// Content-Type: application/json
///
/// Body:
/// {
///   "room_name": "...",
///   "participant_name": "..."
/// }
///
/// Réponse:
/// {
///   "serverUrl": "...",
///   "participantToken": "...",
///   "roomName": "...",
///   "participantName": "..."
/// }
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance =
      LiveKitService._();

  /// Récupère les credentials nécessaires à Room.connect().
  ///
  /// Retourne uniquement le participantToken.
  ///
  /// Le serverUrl retourné par LiveKit est stocké dans
  /// [lastServerUrl] afin que le caller puisse l'utiliser.
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final roomName = room.trim();
    final participantName = name.trim();

    if (roomName.isEmpty) {
      _err('Room name is empty');
      return null;
    }

    if (identity.trim().isEmpty) {
      _err('Participant identity is empty');
      return null;
    }

    if (participantName.isEmpty) {
      _err('Participant name is empty');
      return null;
    }

    try {
      final uri = Uri.parse(
        AppConfig.livekitSandboxApi,
      );

      developer.log(
        '🔌 Requesting LiveKit sandbox credentials',
        level: 800,
      );

      final response = await http
          .post(
            uri,
            headers: {
              'X-Sandbox-ID':
                  AppConfig.livekitSandboxId,
              'Content-Type':
                  'application/json',
              'Accept':
                  'application/json',
            },
            body: jsonEncode({
              'room_name': roomName,
              'participant_name': participantName,
            }),
          )
          .timeout(
            AppConfig.tokenTimeout,
          );

      developer.log(
        'LiveKit token server response: '
        '${response.statusCode}',
        level: 800,
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw HttpFailureException(
          response.statusCode,
          _extractError(response.body),
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Réponse LiveKit invalide.',
        );
      }

      final participantToken =
          decoded['participantToken'] as String?;

      final serverUrl =
          decoded['serverUrl'] as String?;

      if (participantToken == null ||
          participantToken.isEmpty) {
        throw const FormatException(
          'Le serveur LiveKit n\'a pas retourné participantToken.',
        );
      }

      if (serverUrl == null ||
          serverUrl.isEmpty) {
        throw const FormatException(
          'Le serveur LiveKit n\'a pas retourné serverUrl.',
        );
      }

      // On conserve l'URL retournée par LiveKit.
      lastServerUrl = serverUrl;

      lastRoomName =
          decoded['roomName'] as String? ?? roomName;

      lastParticipantName =
          decoded['participantName'] as String? ??
              participantName;

      developer.log(
        '✅ LiveKit credentials received',
        level: 800,
      );

      developer.log(
        '   serverUrl=$serverUrl',
        level: 800,
      );

      developer.log(
        '   room=$lastRoomName',
        level: 800,
      );

      developer.log(
        '   participant=$lastParticipantName',
        level: 800,
      );

      return participantToken;
    } on TimeoutException catch (e) {
      _err(
        'LiveKit token server timeout: $e',
      );
      return null;
    } on HttpFailureException catch (e) {
      _err(
        'LiveKit token server HTTP error: $e',
      );
      return null;
    } on FormatException catch (e) {
      _err(
        'LiveKit response format error: $e',
      );
      return null;
    } catch (e, stackTrace) {
      developer.log(
        '❌ LiveKitService.fetchToken failed',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );

      return null;
    }
  }

  /// URL LiveKit retournée par le sandbox.
  String? lastServerUrl;

  /// Nom de la room retourné par LiveKit.
  String? lastRoomName;

  /// Nom du participant retourné par LiveKit.
  String? lastParticipantName;

  /// Récupère le message d'erreur du serveur.
  String _extractError(String body) {
    if (body.trim().isEmpty) {
      return 'Réponse vide du serveur LiveKit.';
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        final error =
            decoded['error'] ??
            decoded['message'] ??
            decoded['detail'];

        if (error != null) {
          return error.toString();
        }
      }
    } catch (_) {
      // La réponse n'est pas du JSON.
    }

    return body.length > 500
        ? body.substring(0, 500)
        : body;
  }

  void _err(String message) {
    developer.log(
      '❌ LiveKitService: $message',
      level: 1000,
    );
  }
}

/// Erreur HTTP du serveur LiveKit.
class HttpFailureException implements Exception {
  final int statusCode;
  final String message;

  HttpFailureException(
    this.statusCode,
    this.message,
  );

  @override
  String toString() {
    return 'HTTP $statusCode — $message';
  }
}

/// Compatibilité avec d'éventuels anciens appels.
typedef DeprecatedTimeoutException =
    TimeoutException;
