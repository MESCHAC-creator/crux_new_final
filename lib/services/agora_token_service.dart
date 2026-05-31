import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/agora_config.dart';
import 'error_handler_service.dart';

class AgoraTokenService {
  static final AgoraTokenService _instance = AgoraTokenService._internal();
  final _logger = Logger();
  final _errorHandler = ErrorHandlerService();

  factory AgoraTokenService() {
    return _instance;
  }

  AgoraTokenService._internal();

  Future<String> getToken({
    required String channelName,
    required int uid,
  }) async {
    try {
      _logger.i('🔑 Demande token pour canal: $channelName (UID: $uid)');

      final url = '${AgoraConfig.tokenServerUrl}/rtc/$channelName/publisher/uid/$uid';
      _logger.i('📡 URL: $url');

      final response = await http.get(
        Uri.parse(url),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('⏱️ Délai d\'attente dépassé lors de la récupération du token');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['rtcToken'] ?? '';

        if (token.isEmpty) {
          throw Exception('❌ Token vide reçu du serveur');
        }

        _logger.i('✅ Token reçu avec succès (${token.length} caractères)');
        return token;
      } else {
        throw Exception(
          '❌ Erreur serveur: ${response.statusCode}\nRéponse: ${response.body}',
        );
      }
    } catch (e) {
      _logger.e('❌ Erreur token: $e');
      _errorHandler.logError('AgoraTokenService', 'getToken: $e');
      throw Exception('❌ Impossible de récupérer le token: $e');
    }
  }

  Future<bool> validateToken(String token) async {
    try {
      if (token.isEmpty) {
        throw Exception('Token vide');
      }
      _logger.i('✅ Token valide');
      return true;
    } catch (e) {
      _logger.e('❌ Token invalide: $e');
      return false;
    }
  }
}