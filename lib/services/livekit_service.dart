import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Service LiveKit utilisant le serveur Sandbox officiel LiveKit.
///
/// IMPORTANT:
/// Ce serveur est destiné au prototypage/développement.
/// Il ne doit pas être considéré comme une architecture de production.
///
/// Endpoint:
/// POST https://cloud-api.livekit.io/api/sandbox/connection-details
///
/// Header:
/// X-Sandbox-ID: crux-6l6num
///
/// Body:
/// {
///   "room_name": "...",
///   "participant_name": "..."
/// }
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  // ══════════════════════════════════════════════════════════════════════
  // LIVEKIT SANDBOX
  // ══════════════════════════════════════════════════════════════════════

  static const String _sandboxEndpoint =
      'https://cloud-api.livekit.io/api/sandbox/connection-details';

  static const String _sandboxId = 'crux-6l6num';

  // ══════════════════════════════════════════════════════════════════════
  // FETCH TOKEN
  // ══════════════════════════════════════════════════════════════════════

  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final normalizedRoom = room.trim();
    final normalizedIdentity = identity.trim();
    final normalizedName = name.trim();

    // ────────────────────────────────────────────────────────────────────
    // Validation
    // ────────────────────────────────────────────────────────────────────

    if (normalizedRoom.isEmpty) {
      _error('Room name is empty.');
      return null;
    }

    if (normalizedIdentity.isEmpty) {
      _error('Participant identity is empty.');
      return null;
    }

    final participantName = normalizedName.isEmpty
        ? normalizedIdentity
        : normalizedName;

    // ────────────────────────────────────────────────────────────────────
    // Diagnostic
    // ────────────────────────────────────────────────────────────────────

    if (isHost) {
      developer.log(
        'Generating LiveKit token for HOST',
        name: 'CRUX.LiveKit',
      );
    }

    if (kDebugMode) {
      developer.log(
        'LiveKit Sandbox request: '
        'room=$normalizedRoom '
        'identity=$normalizedIdentity '
        'name=$participantName',
        name: 'CRUX.LiveKit',
      );
    }

    // ════════════════════════════════════════════════════════════════════
    // REQUEST
    // ════════════════════════════════════════════════════════════════════

    try {
      final response = await http
          .post(
            Uri.parse(_sandboxEndpoint),
            headers: const {
              'X-Sandbox-ID': _sandboxId,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'room_name': normalizedRoom,
              'participant_name': participantName,
            }),
          )
          .timeout(
            AppConfig.tokenTimeout,
          );

      // ═════════════════════════════════════════════════════════════════
      // HTTP ERROR
      // ═════════════════════════════════════════════════════════════════

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final errorMessage = _extractErrorMessage(
          response.body,
        );

        _error(
          'LiveKit Sandbox HTTP ${response.statusCode}: '
          '$errorMessage',
        );

        return null;
      }

      // ═════════════════════════════════════════════════════════════════
      // PARSE JSON
      // ═════════════════════════════════════════════════════════════════

      final dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (e) {
        _error(
          'Invalid JSON returned by LiveKit Sandbox: $e',
        );
        return null;
      }

      if (decoded is! Map<String, dynamic>) {
        _error(
          'LiveKit Sandbox returned an invalid JSON object.',
        );
        return null;
      }

      // ═════════════════════════════════════════════════════════════════
      // PARTICIPANT TOKEN
      // ═════════════════════════════════════════════════════════════════

      final participantToken =
          decoded['participantToken'];

      if (participantToken is! String ||
          participantToken.trim().isEmpty) {
        _error(
          'LiveKit Sandbox response does not contain '
          'a valid participantToken.',
        );
        return null;
      }

      // ═════════════════════════════════════════════════════════════════
      // SERVER URL
      // ═════════════════════════════════════════════════════════════════

      final serverUrl =
          decoded['serverUrl'];

      if (serverUrl is String &&
          serverUrl.isNotEmpty &&
          serverUrl != AppConfig.livekitWssUrl) {
        developer.log(
          'LiveKit server returned: $serverUrl',
          name: 'CRUX.LiveKit',
        );
      }

      // ═════════════════════════════════════════════════════════════════
      // ROOM VALIDATION
      // ═════════════════════════════════════════════════════════════════

      final returnedRoom =
          decoded['roomName'];

      if (returnedRoom is String &&
          returnedRoom.isNotEmpty &&
          returnedRoom != normalizedRoom) {
        developer.log(
          'Warning: returned room differs from requested room. '
          'requested=$normalizedRoom returned=$returnedRoom',
          name: 'CRUX.LiveKit',
        );
      }

      // ═════════════════════════════════════════════════════════════════
      // SUCCESS
      // ═════════════════════════════════════════════════════════════════

      developer.log(
        'LiveKit token received successfully.',
        name: 'CRUX.LiveKit',
      );

      return participantToken.trim();
    } on TimeoutException catch (e, stackTrace) {
      _error(
        'LiveKit Sandbox timeout: $e',
        stackTrace,
      );
      return null;
    } on http.ClientException catch (e, stackTrace) {
      _error(
        'LiveKit Sandbox network error: $e',
        stackTrace,
      );
      return null;
    } catch (e, stackTrace) {
      _error(
        'Unexpected LiveKit Sandbox error: $e',
        stackTrace,
      );
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // ERROR PARSER
  // ══════════════════════════════════════════════════════════════════════

  String _extractErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return 'Empty response.';
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] != null) {
          return decoded['error'].toString();
        }

        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {
      // On utilise la réponse brute ci-dessous.
    }

    if (body.length > 500) {
      return '${body.substring(0, 500)}...';
    }

    return body;
  }

  // ══════════════════════════════════════════════════════════════════════
  // LOGGING
  // ══════════════════════════════════════════════════════════════════════

  void _error(
    String message, [
    StackTrace? stackTrace,
  ]) {
    developer.log(
      message,
      name: 'CRUX.LiveKit',
      level: 1000,
      stackTrace: stackTrace,
    );
  }
}
