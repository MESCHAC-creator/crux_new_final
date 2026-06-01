import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';
import 'error_handler_service.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = Logger();
  final _errorHandler = ErrorHandlerService();

  factory MeetingService() => _instance;
  MeetingService._internal();

  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
  }) async {
    try {
      _logger.i('📝 Création réunion: $title');

      final now = DateTime.now();
      final meetingId = _firestore.collection('meetings').doc().id;

      final meeting = MeetingModel(
        id: meetingId,
        title: title,
        description: description,
        organizer: organizerName,
        organizerId: organizerId,
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        participants: [organizerId],
        channelName: meetingId,
        status: MeetingStatus.scheduled,
        createdAt: now,
      );

      await _firestore.collection('meetings').doc(meetingId).set(meeting.toJson());

      _logger.i('✅ Réunion créée: $meetingId');
      return meetingId;
    } catch (e) {
      _logger.e('❌ Erreur création: $e');
      _errorHandler.logError('MeetingService', 'createMeeting: $e');
      throw Exception('❌ Impossible de créer la réunion: $e');
    }
  }

  Stream<MeetingModel?> getMeeting(String meetingId) {
    return _firestore.collection('meetings').doc(meetingId).snapshots().map((snap) {
      if (snap.exists) {
        _logger.i('📋 Réunion récupérée: $meetingId');
        return MeetingModel.fromJson(snap.data()!);
      }
      return null;
    });
  }

  Future<void> updateMeetingStatus(String meetingId, MeetingStatus status) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'status': status.toString().split('.').last,
      });
      _logger.i('✅ Statut mis à jour: ${status.toString().split('.').last}');
    } catch (e) {
      _logger.e('❌ Erreur mise à jour: $e');
      _errorHandler.logError('MeetingService', 'updateMeetingStatus: $e');
    }
  }

  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayUnion([userId]),
      });
      _logger.i('✅ Participant ajouté: $userId');
    } catch (e) {
      _logger.e('❌ Erreur ajout participant: $e');
    }
  }

  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayRemove([userId]),
      });
      _logger.i('✅ Participant supprimé: $userId');
    } catch (e) {
      _logger.e('❌ Erreur suppression participant: $e');
    }
  }
}
