import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meeting_model.dart';
import '../utils/logger.dart' as crux;

/// Service pour communiquer avec le backend API CRUX
/// Gère la création et la récupération des réunions via le serveur Node.js
class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // URL du backend - à configurer selon votre environnement
  static const String _baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  factory BackendApiService() => _instance;
  BackendApiService._internal();

  /// Récupère le token Firebase actuel
Future<String> _getAuthToken() async {
  final user = _auth.currentUser;
  if (user == null) {
    throw Exception('Utilisateur non authentifié');
  }
  final token = await user.getIdToken();
  if (token == null) {
    throw Exception('Impossible de récupérer le token utilisateur');
  }
  return token;
}

  /// Crée une nouvelle réunion via le backend
  Future<Map<String, dynamic>> createMeeting({
    required String title,
    String description = '',
    required String organizerName,
    String? passcode,
    bool isLargeConference = false,
  }) async {
    try {
      final token = await _getAuthToken();
      
      final response = await http.post(
        Uri.parse('$_baseUrl/api/meetings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'description': description,
          'organizerName': organizerName,
          'passcode': passcode,
          'isLargeConference': isLargeConference,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        crux.logger.i('✅ Réunion créée via backend: ${data['id']}');
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur création réunion');
      }
    } catch (e) {
      crux.logger.e('❌ BackendApiService.createMeeting error', error: e);
      rethrow;
    }
  }

  /// Récupère une réunion par son code via le backend
  Future<Map<String, dynamic>?> getMeetingByCode(String code) async {
    try {
      final token = await _getAuthToken();
      
      final response = await http.get(
        Uri.parse('$_baseUrl/api/meetings/code/$code'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        crux.logger.i('✅ Réunion trouvée par code: $code');
        return data;
      } else if (response.statusCode == 404) {
        crux.logger.w('⚠️ Réunion non trouvée pour le code: $code');
        return null;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur récupération réunion');
      }
    } catch (e) {
      crux.logger.e('❌ BackendApiService.getMeetingByCode error', error: e);
      rethrow;
    }
  }

  /// Récupère une réunion par son ID via le backend
  Future<Map<String, dynamic>?> getMeetingById(String id) async {
    try {
      final token = await _getAuthToken();
      
      final response = await http.get(
        Uri.parse('$_baseUrl/api/meetings/$id'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        crux.logger.i('✅ Réunion trouvée par ID: $id');
        return data;
      } else if (response.statusCode == 404) {
        crux.logger.w('⚠️ Réunion non trouvée pour l\'ID: $id');
        return null;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur récupération réunion');
      }
    } catch (e) {
      crux.logger.e('❌ BackendApiService.getMeetingById error', error: e);
      rethrow;
    }
  }

  /// Ajoute un participant à une réunion via le backend
  Future<void> addParticipant(String meetingId) async {
    try {
      final token = await _getAuthToken();
      
      final response = await http.put(
        Uri.parse('$_baseUrl/api/meetings/$meetingId/participants'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        crux.logger.i('✅ Participant ajouté à la réunion: $meetingId');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur ajout participant');
      }
    } catch (e) {
      crux.logger.e('❌ BackendApiService.addParticipant error', error: e);
      rethrow;
    }
  }

  /// Récupère un token LiveKit pour rejoindre une réunion
  Future<Map<String, dynamic>> getLiveKitToken({
    required String room,
    required String identity,
    required String name,
    bool isHost = false,
  }) async {
    try {
      final token = await _getAuthToken();
      
      final uri = Uri.parse('$_baseUrl/api/livekit-token').replace(
        queryParameters: {
          'room': room,
          'identity': identity,
          'name': name,
          if (isHost) 'isHost': 'true',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        crux.logger.i('✅ Token LiveKit obtenu pour la room: $room');
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur génération token');
      }
    } catch (e) {
      crux.logger.e('❌ BackendApiService.getLiveKitToken error', error: e);
      rethrow;
    }
  }

  /// Convertit les données du backend en MeetingModel
  MeetingModel? parseMeetingData(Map<String, dynamic>? data) {
    if (data == null) return null;
    
    try {
      return MeetingModel.fromJson(data);
    } catch (e) {
      crux.logger.e('❌ Erreur parsing meeting data', error: e);
      return null;
    }
  }
}
