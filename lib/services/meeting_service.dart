import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';
import '../models/scheduled_meeting_model.dart';
export '../models/meeting_model.dart';
export '../models/scheduled_meeting_model.dart';

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

      final meetingId =
          const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
      final meetingCode = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 8)
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
        meetingCode: meetingCode,
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

  /// Crée une réunion planifiée avec support complet des champs professionnels.
  /// Ceci est la nouvelle méthode pour Phase 1-3 de la roadmap.
  Future<ScheduledMeetingModel> scheduleProMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerEmail,
    DateTime? startTime,
    DateTime? endTime,
    String timezone = 'UTC',
    String? passcode,
    bool waitingRoomEnabled = false,
    bool allowBeforeHost = false,
    bool disableGuests = false,
    bool cameraEnabled = true,
    bool microphoneEnabled = true,
    bool screenShareEnabled = true,
    bool chatEnabled = true,
    bool reactionsEnabled = true,
    bool recordAutomatically = false,
    String recordingType = 'none',
    List<String> invitedEmails = const [],
    bool notifyAtOneHour = true,
    bool notifyAtFifteenMin = true,
    bool notifyAtFiveMin = true,
    bool notifyAtStart = true,
    MeetingType meetingType = MeetingType.standard,
    bool isLargeConference = false,
    Map<String, dynamic> customSettings = const {},
  }) async {
    try {
      final userId = _getCurrentUserId();
      final now = DateTime.now();
      final start = startTime ?? now.add(const Duration(hours: 1));
      final end = endTime ?? start.add(const Duration(hours: 1));

      // Validation
      if (start.isBefore(now.subtract(const Duration(minutes: 5)))) {
        throw Exception('start_time_in_past');
      }
      if (end.isBefore(start)) {
        throw Exception('end_time_before_start');
      }

      final meetingId = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 12)
          .toUpperCase();
      final meetingCode = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 8)
          .toUpperCase();
      final meetingLink = 'https://crux-app.web/join/$meetingId';

      // Validation passcode
      if (passcode != null &&
          passcode.isNotEmpty &&
          (passcode.length < 4 || passcode.length > 6)) {
        throw Exception('passcode_invalid_length');
      }
      if (passcode != null &&
          passcode.isNotEmpty &&
          !RegExp(r'^\d+$').hasMatch(passcode)) {
        throw Exception('passcode_must_be_digits');
      }

      final meeting = ScheduledMeetingModel(
        id: meetingId,
        title: title,
        description: description,
        organizerId: userId,
        organizerName: organizerName,
        organizerEmail: organizerEmail,
        createdAt: now,
        scheduledStart: start,
        scheduledEnd: end,
        timezone: timezone,
        status: ScheduledMeetingStatus.scheduled,
        passcode: passcode?.isNotEmpty == true ? passcode : null,
        waitingRoomEnabled: waitingRoomEnabled,
        allowBeforeHost: allowBeforeHost,
        disableGuests: disableGuests,
        cameraEnabled: cameraEnabled,
        microphoneEnabled: microphoneEnabled,
        screenShareEnabled: screenShareEnabled,
        chatEnabled: chatEnabled,
        reactionsEnabled: reactionsEnabled,
        recordAutomatically: recordAutomatically,
        recordingType: recordingType,
        participants: [userId],
        invitedEmails: invitedEmails,
        coHosts: [],
        notifyAtOneHour: notifyAtOneHour,
        notifyAtFifteenMin: notifyAtFifteenMin,
        notifyAtFiveMin: notifyAtFiveMin,
        notifyAtStart: notifyAtStart,
        meetingLink: meetingLink,
        meetingCode: meetingCode,
        meetingType: meetingType,
        isLargeConference: isLargeConference,
        settings: customSettings,
      );

      bool written = false;
      for (int attempt = 0; attempt < 3 && !written; attempt++) {
        try {
          await _firestore
              .collection('scheduled_meetings')
              .doc(meetingId)
              .set(meeting.toJson());
          written = true;
          _log.i(
              '✅ Réunion planifiée créée: $meetingId (${meeting.scheduledStart})');
        } catch (e) {
          _log.w('scheduleProMeeting attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
          }
        }
      }

      if (!written) {
        throw Exception('firestore_write_failed');
      }

      return meeting;
    } on FirebaseAuthException catch (e) {
      _log.e('❌ Firebase Auth error: ${e.code}');
      throw Exception('auth_failed: ${e.code}');
    } catch (e) {
      _log.e('❌ scheduleProMeeting error: $e');
      rethrow;
    }
  }

  /// Ancienne méthode scheduleMeeting — conservée pour compatibilité.
  /// Utilise scheduleProMeeting en interne.
  Future<String> scheduleMeeting({
    required String title,
    required String description,
    required String organizerName,
    required DateTime startTime,
    String? passcode,
  }) async {
    try {
      final current = FirebaseAuth.instance.currentUser;

      final meeting = await scheduleProMeeting(
        title: title,
        description: description,
        organizerName: organizerName,
        organizerEmail: current?.email ?? 'unknown@crux.app',
        startTime: startTime,
        passcode: passcode,
      );

      return meeting.id;
    } on FirebaseAuthException catch (e) {
      _log.e('❌ Firebase Auth error: ${e.code}');
      throw Exception('auth_failed: ${e.code}');
    } catch (e) {
      _log.e('❌ scheduleMeeting error: $e');
      rethrow;
    }
  }

  Stream<MeetingModel?> getMeeting(String meetingId) {
    return _firestore.collection('meetings').doc(meetingId).snapshots().map(
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
        final snap =
            await _firestore.collection('meetings').doc(meetingId).get();
        return snap.exists ? MeetingModel.fromJson(snap.data()!) : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Récupère une réunion planifiée par ID.
  Future<ScheduledMeetingModel?> getScheduledMeeting(String meetingId) async {
    try {
      final snap = await _firestore
          .collection('scheduled_meetings')
          .doc(meetingId)
          .get(const GetOptions(source: Source.server));

      if (!snap.exists) return null;
      return ScheduledMeetingModel.fromJson(snap.data()!);
    } catch (e) {
      _log.w('getScheduledMeeting error: $e');
      return null;
    }
  }

  /// Flux des réunions planifiées d'un utilisateur.
  Stream<List<ScheduledMeetingModel>> streamUserScheduledMeetings(
    String userId, {
    ScheduledMeetingStatus? statusFilter,
  }) {
    Query query = _firestore
        .collection('scheduled_meetings')
        .where('participants', arrayContains: userId);

    if (statusFilter != null) {
      final statusStr = statusFilter.toString().split('.').last;
      query = query.where('status', isEqualTo: statusStr);
    }

    query = query.orderBy('scheduledStart');

    return query.snapshots().map((snap) {
      return snap.docs
          .map((d) =>
              ScheduledMeetingModel.fromJson(d.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> updateMeetingStatus(
      String meetingId, MeetingStatus status) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'status': status.toString().split('.').last,
      });
    } catch (e) {
      _log.e('updateMeetingStatus error: $e');
    }
  }

  /// Met à jour le statut d'une réunion planifiée.
  Future<void> updateScheduledMeetingStatus(
      String meetingId, ScheduledMeetingStatus status) async {
    try {
      final data = {
        'status': status.toString().split('.').last,
      };
      if (status == ScheduledMeetingStatus.live) {
        data['actualStart'] = DateTime.now().toIso8601String();
      } else if (status == ScheduledMeetingStatus.ended) {
        data['actualEnd'] = DateTime.now().toIso8601String();
      }
      await _firestore
          .collection('scheduled_meetings')
          .doc(meetingId)
          .update(data);
      _log.i('✅ Statut réunion planifiée mise à jour: $meetingId -> $status');
    } catch (e) {
      _log.e('updateScheduledMeetingStatus error: $e');
    }
  }

  /// Annule une réunion planifiée.
  Future<void> cancelScheduledMeeting(String meetingId,
      {String reason = 'Cancelled by organizer'}) async {
    try {
      await _firestore.collection('scheduled_meetings').doc(meetingId).update({
        'status': 'cancelled',
        'cancellationReason': reason,
      });
      _log.i('✅ Réunion planifiée annulée: $meetingId');
    } catch (e) {
      _log.e('cancelScheduledMeeting error: $e');
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

  /// Ajoute un participant à une réunion planifiée.
  Future<void> addParticipantToScheduled(
      String meetingId, String userId) async {
    try {
      await _firestore
          .collection('scheduled_meetings')
          .doc(meetingId)
          .update({
        'participants': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      _log.e('addParticipantToScheduled error: $e');
    }
  }

  /// Supprime un participant d'une réunion planifiée.
  Future<void> removeParticipantFromScheduled(
      String meetingId, String userId) async {
    try {
      await _firestore
          .collection('scheduled_meetings')
          .doc(meetingId)
          .update({
        'participants': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      _log.e('removeParticipantFromScheduled error: $e');
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

  Future<void> registerPresence(
      String meetingId, String userId, String userName) async {
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

  Future<void> saveMeetingHistoryForUser({
    required String meetingId,
    required String userId,
    required String title,
    required int durationSeconds,
    bool endMeeting = false,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final historyRef = userRef.collection('meeting_history').doc(meetingId);
      final meetingRef = _firestore.collection('meetings').doc(meetingId);
      final safeDuration = durationSeconds < 0 ? 0 : durationSeconds;

      await _firestore.runTransaction((transaction) async {
        final existingHistory = await transaction.get(historyRef);
        transaction.set(
          historyRef,
          {
            'meetingId': meetingId,
            'title': title,
            'duration': safeDuration,
            'endedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (!existingHistory.exists) {
          transaction.set(
            userRef,
            {
              'meetingCount': FieldValue.increment(1),
              'totalDuration': FieldValue.increment(safeDuration),
            },
            SetOptions(merge: true),
          );
        }
        if (endMeeting) {
          transaction.set(
            meetingRef,
            {
              'status': MeetingStatus.ended.toString().split('.').last,
              'endedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });
    } catch (e) {
      _log.e('saveMeetingHistoryForUser error: $e');
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

  /// Ajoute un co-hôte à une réunion planifiée.
  Future<void> addCoHostToScheduled(String meetingId, String userId) async {
    try {
      await _firestore
          .collection('scheduled_meetings')
          .doc(meetingId)
          .update({
        'coHosts': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      _log.e('addCoHostToScheduled error: $e');
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
