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

  factory MeetingService() => _instance;
  MeetingService._internal();

  /// Generates a short uppercase meeting code.
  String generateMeetingCode() {
    const Uuid _uuid = Uuid();
    return _uuid.v4().replaceAll('-', '').substring(0, 12).toUpperCase();
  }

  /// Returns recent meetings stored locally for [userId].
  Future<List<Map<String, dynamic>>> getRecentMeetings(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('crux_recent_meetings_$userId') ?? '[]';
      return List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  /// Saves [entry] to the front of the local recent-meetings list for [userId].
  Future<void> saveRecentMeeting(String userId, Map<String, dynamic> entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'crux_recent_meetings_$userId';
      final raw = prefs.getString(key) ?? '[]';
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
      list.removeWhere((e) => e['id'] == entry['id']);
      list.insert(0, entry);
      if (list.length > 20) list.removeLast();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  /// Generates the meeting ID locally (UUID) so creation NEVER fails
  /// even if Firestore is unavailable. Firestore persistence is best-effort.
  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
    String? passcode,
    String? password,        // alias for passcode (old API compat)
    DateTime? scheduledAt,
    bool waitingRoom = false,
    int? maxParticipants,
    String? meetingMode,
    String? existingCode,
  }) async {
    final effectivePasscode = passcode ?? password;
    // Use provided code or generate one locally — works offline
    final meetingId = existingCode ?? const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
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
      passcode: effectivePasscode?.isNotEmpty == true ? effectivePasscode : null,
    );

    // Build base doc data and merge optional extra fields
    final docData = meeting.toJson();
    if (scheduledAt != null) docData['scheduledAt'] = scheduledAt.toIso8601String();
    if (waitingRoom) docData['waitingRoom'] = true;
    if (maxParticipants != null) docData['maxParticipants'] = maxParticipants;
    if (meetingMode != null) docData['meetingMode'] = meetingMode;

    // Try to persist to Firestore — non-blocking, never throws
    _firestore
        .collection('meetings')
        .doc(meetingId)
        .set(docData)
        .then((_) => _log.i('✅ Réunion persistée dans Firestore: $meetingId'))
        .catchError((e) => _log.w('⚠️ Firestore indisponible, réunion locale uniquement: $e'));

    return meetingId;
  }

  Stream<MeetingModel?> getMeeting(String meetingId) {
    return _firestore.collection('meetings').doc(meetingId).snapshots().map(
      (snap) => snap.exists ? MeetingModel.fromJson(snap.data()!) : null,
    );
  }

  /// Fetch meeting once — used for passcode checks before joining.
  Future<MeetingModel?> getMeetingOnce(String meetingId) async {
    try {
      final snap = await _firestore.collection('meetings').doc(meetingId).get();
      return snap.exists ? MeetingModel.fromJson(snap.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateMeetingStatus(String meetingId, MeetingStatus status) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'status': status.toString().split('.').last,
      });
    } catch (_) {}
  }

  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayUnion([userId]),
      });
    } catch (_) {}
  }

  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId).update({
        'participants': FieldValue.arrayRemove([userId]),
      });
    } catch (_) {}
  }

  Future<void> registerPresence(String meetingId, String userId, String userName) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .collection('presence').doc(userId).set({
        'userId': userId,
        'name': userName,
        'micOn': true,
        'camOn': true,
        'handRaised': false,
        'isSpeaking': false,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> removePresence(String meetingId, String userId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .collection('presence').doc(userId).delete();
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> streamPresence(String meetingId) {
    return _firestore.collection('meetings').doc(meetingId)
        .collection('presence')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> setLocked(String meetingId, bool locked) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'isLocked': locked});
    } catch (_) {}
  }

  Future<void> triggerMuteAll(String meetingId) async {
    try {
      await _firestore.collection('meetings').doc(meetingId)
          .update({'muteAllCount': FieldValue.increment(1)});
    } catch (_) {}
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
}
