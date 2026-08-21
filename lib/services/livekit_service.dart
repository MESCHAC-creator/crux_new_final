import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// **LiveKitService** — Token server résilient multi-backend multi-path.
///
/// Pipeline d'appel (15 s max par tentative) :
///   1. [LIVEKIT_TOKEN_SERVER_URL] + `/livekit-token`
///   2. [LIVEKIT_TOKEN_SERVER_URL] + `/api/livekit-token`
///   3. Chaque URL de [LIVEKIT_FALLBACK_URLS] (debug only) dans l'ordre,
///      avec les deux paths ci-dessus.
///
/// Toute requête transmet un `Authorization: Bearer <Firebase ID Token>`.
/// Le backend rejette systématiquement `identity != request.auth.uid`.
class LiveKitService {
  LiveKitService._();
  static final LiveKitService instance = LiveKitService._();

  static const List<String> _endpoints = [
    '/livekit-token',
    '/api/livekit-token',
  ];

  /// Retourne un JWT LiveKit valide ou `null` si tous les backends ont échoué.
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _err('User not authenticated');
      return null;
    }

    // Vérification locale d'identité avant même de sortir
    if (identity != user.uid) {
      _err('Identity mismatch (identity=$identity, uid=${user.uid})');
      return null;
    }

    String idToken;
    try {
      idToken = await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      _err('Firebase getToken error: ${e.code} ${e.message}');
      return null;
    }
    if (idToken.isEmpty) {
      _err('Empty Firebase ID token');
      return null;
    }

    final query = <String, String>{
      'room': room.trim(),
      'identity': identity.trim(),
      'name': name.trim(),
      'isHost': isHost.toString(),
    };

    final serverUrls = <String>[
      if (AppConfig.livekitTokenServerUrl.isNotEmpty)
        AppConfig.livekitTokenServerUrl,
      ...AppConfig.livekitFallbackUrls,
    ];

    if (serverUrls.isEmpty) {
      _err('Aucun serveur de tokens configuré (LIVEKIT_TOKEN_SERVER_URL)');
      return null;
    }

    // Log le diagnostic (n'apparaît qu'en debug/profile)
    if (kDebugMode) {
      developer.log(
        '📋 LiveKitService: serverUrls=${serverUrls.length} | room=$room | uid=$identity | host=$isHost',
        level: 800,
      );
    }

    String? lastError;
    for (final baseUrl in serverUrls) {
      for (final endpoint in _endpoints) {
        final uri = _buildUri(baseUrl, endpoint, query);
        try {
          final token = await _request(uri, idToken);
          developer.log(
            '✅ LiveKitService: token from $baseUrl$endpoint '
            '(${token.length} chars, room=$room, host=$isHost)',
            level: 800,
          );
          return token;
        } catch (e) {
          lastError = '$e';
          developer.log(
            '⚠️  LiveKitService: $baseUrl$endpoint failed — $e',
            level: 900,
          );
        }
      }
    }

    _err('Tous les serveurs de tokens ont échoué. Dernier : $lastError');
    return null;
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Uri _buildUri(String base, String endpoint, Map<String, String> query) {
    var baseUrl = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (baseUrl.endsWith(endpoint)) {
      baseUrl = baseUrl.substring(0, baseUrl.length - endpoint.length);
    }
    return Uri.parse('$baseUrl$endpoint').replace(queryParameters: query);
  }

  Future<String> _request(Uri uri, String idToken) async {
    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'User-Agent': 'crux-flutter/${AppConfig.appVersion}',
          },
        )
        .timeout(AppConfig.tokenTimeout);

    if (response.statusCode ~/ 100 != 2) {
      String detail = response.body;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['error'] != null) detail = json['error'].toString();
      } catch (_) {}
      throw HttpFailureException(response.statusCode, detail);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Pas de champ `token` dans la réponse');
    }
    return token;
  }

  void _err(String msg) {
    developer.log('❌ LiveKitService.fetchToken: $msg', level: 1000);
  }
}

class HttpFailureException implements Exception {
  final int statusCode;
  final String message;
  HttpFailureException(this.statusCode, this.message);
  @override
  String toString() => 'HTTP $statusCode — $message';
}

typedef DeprecatedTimeoutException = TimeoutException;
