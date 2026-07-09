import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';
export '../models/meeting_model.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _log = Logger();

  factory MeetingService() => _instance;
  MeetingService._internal();

  /// Vérifie que l'utilisateur est authentifié
  String _getCurrentUserId() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('auth_required');
    }
    return userId;
  }

  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    String? organizerId,
    String? passcode,
    bool isLargeConference = false,
  }) async {
    try {
      // Vérifier l'authentification
      final userId = _getCurrentUserId();
      final finalOrganizerID = organizerId ?? userId;

      final meetingId = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 12)
          .toUpperCase();
      final now = DateTime.now();

      final meeting = MeetingModel(
        id: meetingId,
        title: title,
        description: description,
        organizer: organizerName,
        organizerId: finalOrganizerID,
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        participants: [finalOrganizerID],
        channelName: meetingId,
        status: MeetingStatus.ongoing,
        createdAt: now,
        passcode: passcode?.isNotEmpty == true ? passcode : null,
        isLargeConference: isLargeConference,
      );

      // Retry write with exponential backoff
      bool written = false;
      for (int attempt = 0; attempt < 3 && !written; attempt++) {
        try {
          await _firestore
              .collection('meetings')
              .doc(meetingId)
              .set(meeting.toJson());
          written = true;
          _log.i('✅ Réunion créée: $meetingId');
        } catch (e) {
          _log.w('createMeeting attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
          }
        }
      }
      
      if (!written) {
        _log.e('❌ Écriture Firestore échouée après 3 tentatives');
        throw Exception('firestore_write_failed');
      }

      // Vérifier serveur
      try {
        final snap = await _firestore
            .collection('meetings')
            .doc(meetingId)
            .get(const GetOptions(source: Source.server));
        if (!snap.exists) {
          _log.e('❌ Réunion non trouvée après écriture');
          throw Exception('meeting_verification_failed');
        }
      } catch (e) {
        _log.w('Server verify skipped: $e');
      }

      return meetingId;
    } on FirebaseAuthException catch (e) {
      _log.e('❌ Firebase Auth error: ${e.code}');
      throw Exception('auth_failed: ${e.code}');
    } catch (e) {
      _log.e('❌ createMeeting error: $e');
      rethrow;
    }
  }

  Future<String> scheduleMeeting({
    required String title,
    required String description,
    required String organizerName,
    String? organizerId,
    required DateTime startTime,
    String? passcode,
  }) async {
    try {
      // Vérifier l'authentification
      final userId = _getCurrentUserId();
      final finalOrganizerID = organizerId ?? userId;

      final meetingId = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 12)
          .toUpperCase();

      final meeting = MeetingModel(
        id: meetingId,
        title: title,
        description: description,
        organizer: organizerName,
        organizerId: finalOrganizerID,
        startTime: startTime,
        endTime: startTime.add(const Duration(hours: 1)),
        participants: [finalOrganizerID],
        channelName: meetingId,
        status: MeetingStatus.scheduled,
        createdAt: DateTime.now(),
        passcode: passcode?.isNotEmpty == true ? passcode : null,
      );

      bool written = false;
      for (int attempt = 0; attempt < 3 && !written; attempt++) {
        try {
          await _firestore
              .collection('meetings')
              .doc(meetingId)
              .set(meeting.toJson());
          written = true;
          _log.i('✅ Réunion planifiée: $meetingId');
        } catch (e) {
          _log.w('scheduleMeeting attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
          }
        }
      }
      
      if (!written) {
        throw Exception('firestore_write_failed');
      }

      return meetingId;
    } on FirebaseAuthException catch (e) {
      _log.e('❌ Firebase Auth error: ${e.code}');
      throw Exception('auth_failed: ${e.code}');
    } catch (e) {
      _log.e('❌ scheduleMeeting error: $e');
      rethrow;
    }
  }

  Stream<MeetingModel?> getMeeting(String meetingId) {
    return _firestore
        .collection('meetings')
        .doc(meetingId)
        .snapshots()
        .map(
          (snap) => snap.exists ? MeetingModel.fromJson(snap.data()!) : null,
        );
  }

  Future<MeetingModel?> getMeetingOnce(String meetingId) async {
    try {
      final snap = await _firestore
          .collection('meetings')
          .doc(meetingId)
          .get(const GetOptions(source: Source.server));
      return snap.exists ? MeetingModel.fromJson(snap.data()!) : null;
    } catch (_) {
      try {
        final snap = await _firestore
            .collection('meetings')
            .doc(meetingId)
            .get();
        return snap.exists ? MeetingModel.fromJson(snap.data()!) : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> updateMeetingStatus(String meetingId, MeetingStatus status) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'status': status.toString().split('.').last,
      });
    } catch (e) {
      _log.e('updateMeetingStatus error: $e');
    }
  }

  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      _log.e('addParticipant error: $e');
    }
  }

  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      _log.e('removeParticipant error: $e');
    }
  }

  Future<void> registerPresence(String meetingId, String userId, String userName) async {
    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .collection('presence')
          .doc(userId)
          .set({
            'userId': userId,
            'name': userName,
            'micOn': true,
            'camOn': true,
            'handRaised': false,
            'isSpeaking': false,
            'joinedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      _log.e('registerPresence error: $e');
    }
  }

  Future<void> removePresence(String meetingId, String userId) async {
    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .collection('presence')
          .doc(userId)
          .delete();
    } catch (e) {
      _log.e('removePresence error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> streamPresence(String meetingId) {
    return _firestore
        .collection('meetings')
        .doc(meetingId)
        .collection('presence')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> setLocked(String meetingId, bool locked) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'isLocked': locked,
      });
    } catch (e) {
      _log.e('setLocked error: $e');
    }
  }

  Future<void> triggerMuteAll(String meetingId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'muteAllCount': FieldValue.increment(1),
      });
    } catch (e) {
      _log.e('triggerMuteAll error: $e');
    }
  }

  Future<void> addCoHost(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'coHosts': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      _log.e('addCoHost error: $e');
    }
  }

  Future<void> removeCoHost(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'coHosts': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      _log.e('removeCoHost error: $e');
    }
  }
}
