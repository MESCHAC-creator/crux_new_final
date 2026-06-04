import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';
import 'error_logger.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _log = Logger();

  static const _historyKey = 'crux_recent_meetings';

  factory MeetingService() => _instance;
  MeetingService._internal();

  /// Pre-generate a meeting ID (useful for displaying code before creation).
  String generateMeetingCode() {
    return const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
  }

  /// Generates meeting ID locally so creation NEVER fails offline.
  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
    String? password,
    DateTime? scheduledAt,
    bool waitingRoom = false,
    int? maxParticipants,
    String? meetingMode,
    String? existingCode,
  }) async {
    final meetingId = existingCode ??
        const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
    final now = DateTime.now();
    final isScheduled = scheduledAt != null && scheduledAt.isAfter(now);
    final startTime = isScheduled ? scheduledAt : now;

    final meeting = MeetingModel(
      id: meetingId,
      title: title,
      description: description,
      organizer: organizerName,
      organizerId: organizerId,
      startTime: startTime,
      endTime: startTime.add(const Duration(hours: 1)),
      participants: [organizerId],
      channelName: meetingId,
      status: MeetingStatus.scheduled,
      createdAt: now,
      password: password?.isNotEmpty == true ? password : null,
      isScheduled: isScheduled,
      scheduledAt: isScheduled ? scheduledAt : null,
      waitingRoom: waitingRoom,
      maxParticipants: maxParticipants,
      meetingMode: meetingMode,
    );

    // Save to history first (fast local operation)
    await _saveToHistory(meetingId, title);

    // Fire-and-forget to Firestore (don't block meeting creation)
    _firestore
        .collection('meetings')
        .doc(meetingId)
        .set(meeting.toJson())
        .then((_) => _log.i('✅ Réunion persistée: $meetingId'))
        .catchError((e) => _log.w('⚠️ Firestore indisponible: $e'));

    return meetingId;
  }

  Stream<MeetingModel?> getMeeting(String meetingId) {
    return _firestore
        .collection('meetings')
        .doc(meetingId)
        .snapshots()
        .map((s) => s.exists ? MeetingModel.fromJson(s.data()!) : null);
  }

  /// Fetch meeting once — used for password/lock checks.
  Future<MeetingModel?> getMeetingOnce(String meetingId) async {
    try {
      final snap =
          await _firestore.collection('meetings').doc(meetingId).get();
      return snap.exists ? MeetingModel.fromJson(snap.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateMeetingStatus(
      String meetingId, MeetingStatus status) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update(
          {'status': status.toString().split('.').last});
    } catch (e) {
      ErrorLogger().logFirestoreError('updateMeetingStatus', meetingId, e);
    }
  }

  Future<void> setLocked(String meetingId, bool locked) async {
    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .update({'isLocked': locked});
    } catch (e) {
      ErrorLogger().logFirestoreError('setLocked', meetingId, e);
    }
  }

  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update(
          {'participants': FieldValue.arrayUnion([userId])});
    } catch (e) {
      ErrorLogger().logFirestoreError('addParticipant', '$meetingId/$userId', e);
    }
  }

  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update(
          {'participants': FieldValue.arrayRemove([userId])});
    } catch (e) {
      ErrorLogger().logFirestoreError('removeParticipant', '$meetingId/$userId', e);
    }
  }

  // ── HISTORY ────────────────────────────────────────────────────────
  Future<void> _saveToHistory(String meetingId, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyKey) ?? [];
      // Keep only unique IDs — remove any existing entry for this ID
      final filtered = raw.where((e) {
        try {
          return (jsonDecode(e) as Map)['id'] != meetingId;
        } catch (_) {
          return false;
        }
      }).toList();

      final entry = jsonEncode({
        'id': meetingId,
        'title': title,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      filtered.insert(0, entry);
      if (filtered.length > 5) filtered.removeLast();
      await prefs.setStringList(_historyKey, filtered);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getRecentMeetings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyKey) ?? [];
      return raw
          .map((e) {
            try {
              return Map<String, dynamic>.from(jsonDecode(e) as Map);
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addCoHost(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'coHosts': FieldValue.arrayUnion([userId])});
    } catch (e) {
      ErrorLogger().logFirestoreError('addCoHost', '$meetingId/$userId', e);
    }
  }

  Future<void> removeCoHost(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'coHosts': FieldValue.arrayRemove([userId])});
    } catch (e) {
      ErrorLogger().logFirestoreError('removeCoHost', '$meetingId/$userId', e);
    }
  }

  Future<void> triggerMuteAll(String meetingId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'muteAllCount': FieldValue.increment(1)});
    } catch (e) {
      ErrorLogger().logFirestoreError('triggerMuteAll', meetingId, e);
    }
  }

  Future<void> registerPresence(String meetingId, String userId, String name) async {
    try {
      await _firestore
          .collection('meetings').doc(meetingId)
          .collection('presence').doc(userId)
          .set({
        'name': name,
        'joinedAt': FieldValue.serverTimestamp(),
        'handRaised': false,
        'camOn': true,
        'isSpeaking': false,
      });
    } catch (e) {
      ErrorLogger().logFirestoreError('registerPresence', '$meetingId/presence/$userId', e);
    }
  }

  Future<void> removePresence(String meetingId, String userId) async {
    try {
      await _firestore
          .collection('meetings').doc(meetingId)
          .collection('presence').doc(userId)
          .delete();
    } catch (e) {
      ErrorLogger().logFirestoreError('removePresence', '$meetingId/presence/$userId', e);
    }
  }

  Stream<List<Map<String, dynamic>>> streamPresence(String meetingId) {
    return _firestore
        .collection('meetings')
        .doc(meetingId)
        .collection('presence')
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'userId': d.id, ...d.data()})
            .toList());
  }
}
