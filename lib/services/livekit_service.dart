import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// LiveKit SFU helpers — token fetch + room limits for large conferences (1000+).
class LiveKitService {
  LiveKitService._();
  static final LiveKitService instance = LiveKitService._();

  /// Fetch a signed JWT from the CRUX token server.
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    List<String> candidates = [];
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.startsWith('http')) {
          candidates.add(origin);
        }
      } catch (_) {}
    }
    candidates.add(AppConfig.livekitTokenServerUrl);
    candidates.add('https://ais-dev-fbrh4wlitwvkmfg4qdhw2f-601651317738.europe-west2.run.app');
    candidates.add('https://ais-pre-fbrh4wlitwvkmfg4qdhw2f-601651317738.europe-west2.run.app');

    // Deduplicate
    final uniqueCandidates = candidates.toSet().toList();

    for (final baseUrl in uniqueCandidates) {
      try {
        final uri = Uri.parse(
          '$baseUrl/livekit-token'
          '?room=${Uri.encodeComponent(room)}'
          '&identity=${Uri.encodeComponent(identity)}'
          '&name=${Uri.encodeComponent(name)}'
          '&host=${isHost ? 'true' : 'false'}',
        );

        dev.log('Trying LiveKit token server: $uri');

        final res = await http.get(uri).timeout(
          const Duration(seconds: 8), // Fast fail-over
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final token = data['token'] as String?;
          if (token != null && token.isNotEmpty) {
            dev.log('Successfully fetched LiveKit token from: $baseUrl');
            return token;
          }
        } else {
          dev.log('Token server $baseUrl returned status ${res.statusCode}');
        }
      } catch (e) {
        dev.log('Error from token server $baseUrl: $e');
      }
    }
    return null;
  }
}
