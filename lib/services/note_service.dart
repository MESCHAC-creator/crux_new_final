import 'package:cloud_firestore/cloud_firestore.dart';

class NoteService {
  static final NoteService instance = NoteService._();
  NoteService._();

  final _db = FirebaseFirestore.instance;

  Future<void> saveMeetingNote({
    required String userId,
    required String meetingId,
    required String meetingName,
    required String content,
  }) async {
    await _db.collection('users').doc(userId).collection('notes').doc(meetingId).set({
      'meetingId': meetingId,
      'meetingName': meetingName,
      'content': content,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot> streamUserNotes(String userId) {
    return _db.collection('users').doc(userId).collection('notes').orderBy('updatedAt', descending: true).snapshots();
  }
}
