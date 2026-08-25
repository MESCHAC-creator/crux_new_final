import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  // ══════════════════════════════════════════════════════════════════════
  // ENDPOINTS
  // ══════════════════════════════════════════════════════════════════════

  static const List<String> _endpoints = [
    '/livekit-token',
    '/api/livekit-token',
  ];

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
    // Validation locale
    // ────────────────────────────────────────────────────────────────────

    if (normalizedRoom.isEmpty) {
      _error('Room vide');
      return null;
    }

    if (normalizedIdentity.isEmpty) {
      _error('Identity vide');
      return null;
    }

    // ────────────────────────────────────────────────────────────────────
    // Firebase
    // ────────────────────────────────────────────────────────────────────

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _error('Utilisateur Firebase non authentifié');
      return null;
    }

    // L'identité LiveKit doit correspondre à l'utilisateur Firebase.
    if (normalizedIdentity != user.uid) {
      _error(
        'Identity mismatch: '
        'identity=$normalizedIdentity '
        'firebaseUid=${user.uid}',
      );
      return null;
    }

    // ────────────────────────────────────────────────────────────────────
    // Firebase ID token
    // ────────────────────────────────────────────────────────────────────

    String idToken;

    try {
      idToken = await user.getIdToken(true) ?? '';
    } on FirebaseAuthException catch (e, stackTrace) {
      _error(
        'Firebase getIdToken failed: '
        '${e.code} — ${e.message}',
        stackTrace,
      );
      return null;
    } catch (e, stackTrace) {
      _error(
        'Firebase getIdToken failed: $e',
        stackTrace,
      );
      return null;
    }

    if (idToken.isEmpty) {
      _error('Firebase ID token vide');
      return null;
    }

    // ════════════════════════════════════════════════════════════════════
    // SERVER URLS
    // ════════════════════════════════════════════════════════════════════

    final serverUrls = <String>[
      if (AppConfig.livekitTokenServerUrl.isNotEmpty)
        AppConfig.livekitTokenServerUrl,
      ...AppConfig.livekitFallbackUrls,
    ];

    final uniqueServerUrls = serverUrls
        .where((url) => url.isNotEmpty)
        .map(_removeTrailingSlash)
        .toSet()
        .toList();

    if (uniqueServerUrls.isEmpty) {
      _error(
        'Aucun serveur de tokens configuré. '
        'Définissez LIVEKIT_TOKEN_SERVER_URL.',
      );
      return null;
    }

    // ════════════════════════════════════════════════════════════════════
    // QUERY
    // ════════════════════════════════════════════════════════════════════

    final query = <String, String>{
      'room': normalizedRoom,
      'identity': normalizedIdentity,
      'name': normalizedName.isEmpty ? normalizedIdentity : normalizedName,
      'isHost': isHost.toString(),
    };

    if (kDebugMode) {
      developer.log(
        'LiveKitService → '
        'servers=${uniqueServerUrls.length} '
        'room=$normalizedRoom '
        'identity=$normalizedIdentity '
        'host=$isHost',
        name: 'CRUX.LiveKit',
      );
    }

    String? lastError;

    // ════════════════════════════════════════════════════════════════════
    // TRY SERVERS
    // ════════════════════════════════════════════════════════════════════

    for (final baseUrl in uniqueServerUrls) {
      for (final endpoint in _endpoints) {
        final uri = _buildUri(
          baseUrl,
          endpoint,
          query,
        );

        try {
          if (kDebugMode) {
            developer.log(
              'Trying token endpoint: $uri',
              name: 'CRUX.LiveKit',
            );
          }

          final token = await _request(
            uri,
            idToken,
          );

          if (token.isEmpty) {
            throw const FormatException(
              'Le serveur a retourné un token vide.',
            );
          }

          if (kDebugMode) {
            developer.log(
              'Token LiveKit reçu '
              '(${token.length} caractères)',
              name: 'CRUX.LiveKit',
            );
          }

          return token;
        } on TimeoutException catch (e, stackTrace) {
          lastError = 'Timeout: $e';

          if (kDebugMode) {
            developer.log(
              'Token endpoint timeout: $uri',
              name: 'CRUX.LiveKit',
              error: e,
              stackTrace: stackTrace,
            );
          }
        } on http.ClientException catch (e, stackTrace) {
          lastError = 'Network: $e';

          if (kDebugMode) {
            developer.log(
              'Network error: $uri',
              name: 'CRUX.LiveKit',
              error: e,
              stackTrace: stackTrace,
            );
          }
        } on HttpFailureException catch (e, stackTrace) {
          lastError = e.toString();

          developer.log(
            'Token server HTTP failure: $uri',
            name: 'CRUX.LiveKit',
            error: e,
            stackTrace: stackTrace,
          );
        } catch (e, stackTrace) {
          lastError = e.toString();

          developer.log(
            'Token endpoint failed: $uri',
            name: 'CRUX.LiveKit',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
    }

    _error(
      'Tous les serveurs de tokens ont échoué. '
      'Dernière erreur: $lastError',
    );

    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // HTTP REQUEST
  // ══════════════════════════════════════════════════════════════════════

  Future<String> _request(
    Uri uri,
    String firebaseIdToken,
  ) async {
    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $firebaseIdToken',
            'Accept': 'application/json',
            'User-Agent': 'CRUX/${AppConfig.appVersion}',
          },
        )
        .timeout(
          AppConfig.tokenTimeout,
        );

    // ────────────────────────────────────────────────────────────────────
    // HTTP ERROR
    // ────────────────────────────────────────────────────────────────────

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HttpFailureException(
        response.statusCode,
        _extractErrorMessage(response.body),
      );
    }

    // ────────────────────────────────────────────────────────────────────
    // JSON
    // ────────────────────────────────────────────────────────────────────

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw FormatException(
        'Réponse JSON invalide du serveur LiveKit: $e',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'La réponse du serveur LiveKit doit être un objet JSON.',
      );
    }

    final tokenValue = decoded['token'];

    if (tokenValue is! String ||
        tokenValue.trim().isEmpty) {
      throw const FormatException(
        'Le champ "token" est absent ou vide.',
      );
    }

    return tokenValue.trim();
  }

  // ══════════════════════════════════════════════════════════════════════
  // URI
  // ══════════════════════════════════════════════════════════════════════

  Uri _buildUri(
    String baseUrl,
    String endpoint,
    Map<String, String> query,
  ) {
    var normalizedBase = _removeTrailingSlash(
      baseUrl,
    );

    final normalizedEndpoint = endpoint.startsWith('/')
        ? endpoint
        : '/$endpoint';

    // Si l'URL fournie contient déjà /livekit-token,
    // on évite de générer :
    //
    // /livekit-token/livekit-token
    //

    if (normalizedBase.endsWith(normalizedEndpoint)) {
      normalizedBase = normalizedBase.substring(
        0,
        normalizedBase.length - normalizedEndpoint.length,
      );
    }

    final uri = Uri.parse(
      '$normalizedBase$normalizedEndpoint',
    );

    return uri.replace(
      queryParameters: query,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ERROR EXTRACTION
  // ══════════════════════════════════════════════════════════════════════

  String _extractErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return 'Réponse vide du serveur.';
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];

        if (error != null) {
          return error.toString();
        }

        final message = decoded['message'];

        if (message != null) {
          return message.toString();
        }
      }
    } catch (_) {
      // On conserve le body brut.
    }

    // Évite d'afficher une réponse serveur gigantesque.
    if (body.length > 500) {
      return '${body.substring(0, 500)}...';
    }

    return body;
  }

  // ══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════

  String _removeTrailingSlash(String value) {
    var result = value.trim();

    while (result.endsWith('/')) {
      result = result.substring(
        0,
        result.length - 1,
      );
    }

    return result;
  }

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

// ══════════════════════════════════════════════════════════════════════════
// HTTP FAILURE
// ══════════════════════════════════════════════════════════════════════════

class HttpFailureException implements Exception {
  final int statusCode;
  final String message;

  const HttpFailureException(
    this.statusCode,
    this.message,
  );

  @override
  String toString() {
    return 'HTTP $statusCode — $message';
  }
}

/// Alias conservé pour compatibilité avec d'éventuels anciens fichiers.
typedef DeprecatedTimeoutException = TimeoutException;
