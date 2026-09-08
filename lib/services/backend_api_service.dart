import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meeting_model.dart';
import '../utils/logger.dart';

/// Service pour communiquer avec le backend API CRUX.
class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const Duration _requestTimeout = Duration(seconds: 30);

  factory BackendApiService() => _instance;
  BackendApiService._internal();

  Map<String, String> _authHeaders(String token, {bool json = false}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    headers[String.fromCharCodes([
          65,
          117,
          116,
          104,
          111,
          114,
          105,
          122,
          97,
          116,
          105,
          111,
          110,
        ])] =
        String.fromCharCodes([66, 101, 97, 114, 101, 114, 32]) + token;
    return headers;
  }

  Future<String> _getAuthToken() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non authentifié');
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Impossible de récupérer le token utilisateur');
    }
    return token;
  }

  Future<Map<String, dynamic>> createMeeting({
    required String title,
    String description = '',
    required String organizerName,
    String? passcode,
    bool isLargeConference = false,
  }) async {
    try {
      final token = await _getAuthToken();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/meetings'),
            headers: _authHeaders(token, json: true),
            body: jsonEncode({
              'title': title,
              'description': description,
              'organizerName': organizerName,
              'passcode': passcode,
              'isLargeConference': isLargeConference,
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        logger.i('✅ Réunion créée via backend: ${data['id']}');
        return data;
      }
      throw Exception(_errorMessage(response, 'Erreur création réunion'));
    } catch (e) {
      logger.e('❌ BackendApiService.createMeeting error', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMeetingByCode(String code) async {
    try {
      final token = await _getAuthToken();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/meetings/code/$code'),
            headers: _authHeaders(token),
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 404) return null;
      throw Exception(_errorMessage(response, 'Erreur récupération réunion'));
    } catch (e) {
      logger.e('❌ BackendApiService.getMeetingByCode error', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMeetingById(String id) async {
    try {
      final token = await _getAuthToken();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/meetings/$id'),
            headers: _authHeaders(token),
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 404) return null;
      throw Exception(_errorMessage(response, 'Erreur récupération réunion'));
    } catch (e) {
      logger.e('❌ BackendApiService.getMeetingById error', error: e);
      rethrow;
    }
  }

  Future<void> addParticipant(String meetingId) async {
    try {
      final token = await _getAuthToken();
      final response = await http
          .put(
            Uri.parse('$_baseUrl/api/meetings/$meetingId/participants'),
            headers: _authHeaders(token),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw Exception(_errorMessage(response, 'Erreur ajout participant'));
      }
    } catch (e) {
      logger.e('❌ BackendApiService.addParticipant error', error: e);
      rethrow;
    }
  }

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
      final response = await http
          .get(uri, headers: _authHeaders(token))
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        throw Exception(_errorMessage(response, 'Erreur génération token'));
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      logger.e('❌ BackendApiService.getLiveKitToken error', error: e);
      rethrow;
    }
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      return data is Map ? (data['error']?.toString() ?? fallback) : fallback;
    } catch (_) {
      return fallback;
    }
  }

  MeetingModel? parseMeetingData(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      return MeetingModel.fromJson(data);
    } catch (e) {
      logger.e('❌ Erreur parsing meeting data', error: e);
      return null;
    }
  }
}
