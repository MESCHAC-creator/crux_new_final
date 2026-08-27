import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

enum LiveKitRole {
  host,
  speaker,
  audience,
}

class LiveKitConnectionDetails {
  final String token;
  final String serverUrl;

  const LiveKitConnectionDetails({
    required this.token,
    required this.serverUrl,
  });
}

class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  Future<LiveKitConnectionDetails?> fetchConnectionDetails({
    required String room,
    required String identity,
    required String name,
    required LiveKitRole role,
  }) async {
    final cleanRoom = room.trim();
    final cleanIdentity = identity.trim();
    final cleanName = name.trim();

    if (cleanRoom.isEmpty ||
        cleanIdentity.isEmpty ||
        cleanName.isEmpty) {
      _logError('Invalid LiveKit connection parameters.');
      return null;
    }

    if (!AppConfig.isLiveKitConfigured) {
      _logError(
        'LiveKit is not configured. '
        'Set LIVEKIT_WSS_URL and LIVEKIT_TOKEN_ENDPOINT.',
      );
      return null;
    }

    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.livekitTokenEndpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'room_name': cleanRoom,
              'participant_identity': cleanIdentity,
              'participant_name': cleanName,

              // Le backend doit utiliser ces informations
              // pour construire les permissions LiveKit.
              'role': role.name,

              'can_publish': role != LiveKitRole.audience,
              'can_subscribe': true,
              'can_publish_data': true,
            }),
          )
          .timeout(AppConfig.tokenTimeout);

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        _logError(
          'Token server returned HTTP ${response.statusCode}: '
          '${response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        _logError('Invalid token server response.');
        return null;
      }

      final token =
          decoded['participantToken']?.toString() ??
          decoded['token']?.toString();

      final serverUrl =
          decoded['serverUrl']?.toString() ??
          AppConfig.livekitWssUrl;

      if (token == null || token.isEmpty) {
        _logError('No participant token returned by backend.');
        return null;
      }

      if (!serverUrl.startsWith('wss://')) {
        _logError('Invalid LiveKit server URL: $serverUrl');
        return null;
      }

      return LiveKitConnectionDetails(
        token: token,
        serverUrl: serverUrl,
      );
    } on TimeoutException {
      _logError('LiveKit token request timed out.');
      return null;
    } on FormatException catch (e) {
      _logError('Invalid JSON from token server: $e');
      return null;
    } catch (e, stackTrace) {
      developer.log(
        'LiveKit connection details request failed.',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );

      return null;
    }
  }

  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final details = await fetchConnectionDetails(
      room: room,
      identity: identity,
      name: name,
      role: isHost
          ? LiveKitRole.host
          : LiveKitRole.audience,
    );

    return details?.token;
  }

  void _logError(String message) {
    developer.log(
      'LiveKitService: $message',
      level: 1000,
    );
  }
}
