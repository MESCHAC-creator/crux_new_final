import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// **LiveKitService** — Service professionnel centralisé pour LiveKit tokens.
/// 
/// PRINCIPES:
/// - Une seule méthode publique: fetchToken()
/// - Récupère automatiquement le Firebase ID Token
/// - Envoie Authorization: Bearer <FirebaseToken>
/// - Timeout strict: 15 secondes
/// - Logs détaillés pour debugging
/// - Gestion des exceptions cohérente
/// - Pas d'URLs hardcodées (AppConfig uniquement)
/// - Retour: String? (JWT ou null en cas d'erreur)
class LiveKitService {
  LiveKitService._();

  static final LiveKitService instance = LiveKitService._();

  /// **fetchToken** — Obtient un JWT LiveKit depuis le backend.
  /// 
  /// Étapes:
  /// 1. Vérifier l'authentification Firebase
  /// 2. Récupérer l'ID token Firebase
  /// 3. Appeler le backend avec Authorization header
  /// 4. Parser la réponse JSON
  /// 5. Retourner le JWT ou null
  /// 
  /// Paramètres:
  /// - room: ID de la room LiveKit (obligatoire)
  /// - identity: Firebase UID du participant (obligatoire)
  /// - name: Nom d'affichage du participant (obligatoire)
  /// - isHost: Si true, crée l'access token avec permissions d'hôte
  /// 
  /// Retour:
  /// - String: JWT valide pour LiveKit
  /// - null: en cas d'erreur (voir logs pour détails)
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    try {
      // Étape 1: Vérifier l'authentification Firebase
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        developer.log(
          '❌ LiveKitService.fetchToken: User not authenticated',
          level: 1000,
        );
        return null;
      }

      developer.log(
        '📋 LiveKitService.fetchToken: Starting token fetch',
        level: 800,
      );

      // Étape 2: Récupérer l'ID token Firebase
      // forceRefresh=true pour s'assurer un token frais
      final idToken = await user.getIdToken(true);

      if (idToken == null || idToken.isEmpty) {
        developer.log(
          '❌ LiveKitService.fetchToken: Failed to get Firebase ID token',
          level: 1000,
        );
        return null;
      }

      developer.log(
        '✅ LiveKitService: Firebase ID token acquired (${idToken.length} chars)',
        level: 800,
      );

      // Étape 3: Préparer la requête HTTP
      final uri = Uri.parse(
        '${AppConfig.livekitTokenServerUrl}/livekit-token',
      ).replace(
        queryParameters: {
          'room': room.trim(),
          'identity': identity.trim(),
          'name': name.trim(),
          'isHost': isHost.toString(),
        },
      );

      developer.log(
        '🌐 LiveKitService: POST ${uri.toString()}',
        level: 800,
      );

      // Étape 4: Envoyer la requête avec Authorization header
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'User-Agent': 'crux-flutter/2.38.1',
            },
          )
          .timeout(
            AppConfig.tokenTimeout,
            onTimeout: () {
              developer.log(
                '❌ LiveKitService.fetchToken: Request timeout after ${AppConfig.tokenTimeout.inSeconds}s',
                level: 1000,
              );
              throw TimeoutException(
                'Token server did not respond within ${AppConfig.tokenTimeout.inSeconds}s',
              );
            },
          );

      developer.log(
        '📡 LiveKitService: HTTP ${response.statusCode}',
        level: 800,
      );

      // Étape 5: Vérifier le code de statut
      if (response.statusCode != 200) {
        developer.log(
          '❌ LiveKitService.fetchToken: Server returned ${response.statusCode}',
          error: response.body,
          level: 1000,
        );
        return null;
      }

      // Étape 6: Parser la réponse JSON
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      final token = body['token'] as String?;
      if (token == null || token.isEmpty) {
        developer.log(
          '❌ LiveKitService.fetchToken: No token in response',
          error: body,
          level: 1000,
        );
        return null;
      }

      developer.log(
        '✅ LiveKitService: Token acquired successfully (${token.length} chars)',
        level: 800,
      );

      return token;
    } on TimeoutException catch (e) {
      developer.log(
        '❌ LiveKitService.fetchToken: Timeout',
        error: e.message,
        level: 1000,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      developer.log(
        '❌ LiveKitService.fetchToken: Firebase Auth error',
        error: '${e.code}: ${e.message}',
        level: 1000,
      );
      return null;
    } catch (e, st) {
      developer.log(
        '❌ LiveKitService.fetchToken: Unexpected error',
        error: e.toString(),
        stackTrace: st,
        level: 1000,
      );
      return null;
    }
  }
}

/// Exception pour les timeouts HTTP
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => 'TimeoutException: $message';
}
