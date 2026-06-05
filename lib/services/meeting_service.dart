import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _log = Logger();

  factory MeetingService() => _instance;
  MeetingService._internal();

  /// Generates the meeting ID locally (UUID) so creation NEVER fails
  /// even if Firestore is unavailable. Firestore persistence is best-effort.
  Future<String> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
    String? passcode,
  }) async {
    // Generate ID locally — works offline
    final meetingId = const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
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
      passcode: passcode?.isNotEmpty == true ? passcode : null,
    );

    // Try to persist to Firestore — non-blocking, never throws
    _firestore
        .collection('meetings')
        .doc(meetingId)
        .set(meeting.toJson())
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
}
