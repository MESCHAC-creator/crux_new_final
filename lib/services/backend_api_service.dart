import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meeting_model.dart';
import '../utils/logger.dart';

/// Service de communication avec le backend API CRUX.
///
/// ⚠️ Note d'audit : Le backend Node (`server.js` / `backend/server.js`)
/// n'est PAS déployé en production (default localhost:3000). Toutes les
/// opérations réellement utilisées par l'app passent par Firestore direct
/// (MeetingService) ou par l'API LiveKit Sandbox (LiveKitService).
///
/// Ce service est conservé pour compatibilité avec `home_screen.dart` et
/// `join_meeting_screen.dart`, mais redirige vers Firestore au lieu
/// d'appeler un backend inexistant. Cela évite le timeout inutile observé
/// sur le web déployé (schac-hub.github.io).
class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Alias de MeetingService.getMeetingByCode — utilise Firestore directement.
  Future<Map<String, dynamic>?> getMeetingByCode(String code) async {
    final upper = code.trim().toUpperCase();
    if (upper.isEmpty) return null;
    try {
      final snap = await _db
          .collection('meetings')
          .where('meetingCode', isEqualTo: upper)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      return {'id': snap.docs.first.id, ...data};
    } catch (e) {
      logger.e('BackendApiService.getMeetingByCode error', error: e);
      return null;
    }
  }

  /// Alias de MeetingService.addParticipant — utilise Firestore directement.
  Future<void> addParticipant(String meetingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Utilisateur non authentifié');
    try {
      await _db.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayUnion([user.uid]),
      });
    } catch (e) {
      logger.e('BackendApiService.addParticipant error', error: e);
      rethrow;
    }
  }

  /// Parseur conservé pour compatibilité.
  MeetingModel? parseMeetingData(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      return MeetingModel.fromJson(data);
    } catch (e) {
      logger.e('Erreur parsing meeting data', error: e);
      return null;
    }
  }
}
