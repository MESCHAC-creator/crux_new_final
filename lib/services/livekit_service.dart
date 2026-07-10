import 'dart:convert';
import 'dart:developer' as dev;
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
    // Primary token server from config
    final baseUrl = AppConfig.livekitTokenServerUrl;
    
    try {
      final uri = Uri.parse(
        '$baseUrl/livekit-token'
        '?room=${Uri.encodeComponent(room)}'
        '&identity=${Uri.encodeComponent(identity)}'
        '&name=${Uri.encodeComponent(name)}'
        '&host=${isHost ? 'true' : 'false'}',
      );

      dev.log('🌐 Fetching LiveKit token from: $uri');

      // Increased timeout to 45s because Render.com free tier takes time to wake up (30-60s)
      final res = await http.get(uri).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          dev.log('❌ Timeout fetching token (Server taking too long to wake up)');
          return http.Response('timeout', 408);
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          dev.log('✅ Successfully fetched LiveKit token');
          return token;
        }
      } else {
        dev.log('❌ Token server returned status ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      dev.log('❌ Error fetching LiveKit token: $e');
    }

    return null;
  }
}
