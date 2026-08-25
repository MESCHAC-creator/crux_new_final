import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  // ═══════════════════════════════════════════════════════════════════════
  // FETCH CONNECTION DETAILS
  // ═══════════════════════════════════════════════════════════════════════

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
      _error('Room name is empty');
      return null;
    }

    if (cleanIdentity.isEmpty) {
      _error('Participant identity is empty');
      return null;
    }

    if (cleanName.isEmpty) {
      _error('Participant name is empty');
      return null;
    }

    try {
      developer.log(
        'Connecting to LiveKit Sandbox '
        'room=$cleanRoom identity=$cleanIdentity host=$isHost',
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
            }),
          )
          .timeout(AppConfig.tokenTimeout);

      developer.log(
        'LiveKit Sandbox response: ${response.statusCode}',
        level: 800,
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        _error(
          'LiveKit Sandbox HTTP ${response.statusCode}: '
          '${response.body}',
        );

        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        _error('Invalid LiveKit response format');
        return null;
      }

      final participantToken =
          decoded['participantToken'] as String?;

      if (participantToken == null ||
          participantToken.isEmpty) {
        _error(
          'LiveKit response does not contain participantToken',
        );

        return null;
      }

      final serverUrl =
          decoded['serverUrl'] as String?;

      if (serverUrl != null && serverUrl.isNotEmpty) {
        developer.log(
          'LiveKit server returned: $serverUrl',
          level: 800,
        );
      }

      final roomName =
          decoded['roomName'] as String?;

      final participantName =
          decoded['participantName'] as String?;

      developer.log(
        'LiveKit connection details received '
        'room=$roomName participant=$participantName',
        level: 800,
      );

      return participantToken;
    } on TimeoutException {
      _error(
        'LiveKit Sandbox request timed out after '
        '${AppConfig.tokenTimeout.inSeconds}s',
      );

      return null;
    } on FormatException catch (e) {
      _error('Invalid LiveKit JSON response: $e');

      return null;
    } catch (e, stackTrace) {
      developer.log(
        'LiveKit token request failed',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );

      return null;
    }
  }

  void _error(String message) {
    developer.log(
      'LiveKitService: $message',
      level: 1000,
    );
  }
}
