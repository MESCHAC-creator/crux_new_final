import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _log = Logger();

  static const _historyKey = 'crux_recent_meetings';

  factory MeetingService() => _instance;
  MeetingService._internal();

  /// Generates meeting ID locally so creation NEVER fails offline.
  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
    String? password,
  }) async {
    final meetingId = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, 16)
        .toUpperCase();
    final now = DateTime.now();

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
      password: password?.isNotEmpty == true ? password : null,
    );

    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .set(meeting.toJson());
      _log.i('✅ Réunion persistée: $meetingId');
    } catch (e) {
      _log.w('⚠️ Firestore indisponible, local seulement: $e');
    }

    await _saveToHistory(meetingId, title);
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
    } catch (_) {}
  }

  Future<void> setLocked(String meetingId, bool locked) async {
    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .update({'isLocked': locked});
    } catch (_) {}
  }

  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update(
          {'participants': FieldValue.arrayUnion([userId])});
    } catch (_) {}
  }

  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update(
          {'participants': FieldValue.arrayRemove([userId])});
    } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> removeCoHost(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'coHosts': FieldValue.arrayRemove([userId])});
    } catch (_) {}
  }

  Future<void> triggerMuteAll(String meetingId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'muteAllCount': FieldValue.increment(1)});
    } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> removePresence(String meetingId, String userId) async {
    try {
      await _firestore
          .collection('meetings').doc(meetingId)
          .collection('presence').doc(userId)
          .delete();
    } catch (_) {}
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
