import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter_foundation/flutter_foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_service.dart';

/// Gestion des tokens LiveKit — SFU helpers pour conférences 1000+ participants.
/// Toutes les URLs de candidats viennent de AppConfig, jamais hardcodées ici.
class LiveKitService {
  LiveKitService._();
  static final LiveKitService instance = LiveKitService._();

  /// Récupère un JWT signé depuis le serveur de tokens CRUX.
  /// Ajoute automatiquement le Firebase ID token dans l'Authorization header.
  Future<String?> fetchToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    final candidates = _buildCandidates();

    for (final baseUrl in candidates) {
      try {
        final token = await _fetchFromCandidate(
          baseUrl: baseUrl,
          room: room,
          identity: identity,
          name: name,
          isHost: isHost,
        );
        if (token != null) return token;
      } catch (e) {
        dev.log('LiveKitService: candidate $baseUrl failed — $e', name: 'crux');
      }
    }

    dev.log('LiveKitService: all candidates exhausted', name: 'crux');
    return null;
  }

  Future<String?> _fetchFromCandidate({
    required String baseUrl,
    required String room,
    required String identity,
    required String name,
    required bool isHost,
  }) async {
    // Obtenir le Firebase ID token pour l'authentification serveur
    final idToken = await AuthService.instance.getIdToken();
    if (idToken == null) {
      dev.log('LiveKitService: no Firebase ID token available', name: 'crux');
      return null;
    }

    final uri = Uri.parse('$baseUrl/livekit-token').replace(
      queryParameters: {
        'room': room,
        'identity': identity,
        'name': Uri.encodeComponent(name),
        'isHost': isHost.toString(),
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token != null && token.isNotEmpty) {
        dev.log('LiveKitService: token obtained from $baseUrl', name: 'crux');
        return token;
      }
    } else {
      dev.log(
        'LiveKitService: HTTP ${response.statusCode} from $baseUrl — ${response.body}',
        name: 'crux',
      );
    }
    return null;
  }

  /// Construit la liste des URLs candidates dans l'ordre de priorité.
  /// Toutes les URLs viennent de AppConfig — aucune valeur hardcodée ici.
  List<String> _buildCandidates() {
    final candidates = <String>{};

    // 1. URL web actuelle (web uniquement)
    if (kIsWeb) {
      try {
        // ignore: undefined_function
        final origin = Uri.base.origin;
        if (origin.startsWith('http')) candidates.add(origin);
      } catch (_) {}
    }

    // 2. URL principale depuis la config
    final primary = AppConfig.livekitTokenServerUrl;
    if (primary.isNotEmpty) candidates.add(primary);

    // 3. URLs de fallback depuis la config (dev/staging)
    for (final url in AppConfig.livekitFallbackUrls) {
      if (url.isNotEmpty) candidates.add(url);
    }

    return candidates.toList();
  }
}
