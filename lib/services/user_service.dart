import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  UserService._();
  static final UserService instance = UserService._();

  final _db = FirebaseFirestore.instance;

  /// Write name and/or photo to the shared Firestore users collection.
  Future<void> saveProfile({
    required String uid,
    String? name,
    String? photoBase64,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) data['name'] = name;
    if (photoBase64 != null) data['photoBase64'] = photoBase64;
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  /// Fetch a user's public profile once.
  Future<Map<String, dynamic>?> getProfile(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null;
    }
  }

  /// Decode a base64 photo string to raw bytes (returns null on failure).
  static Uint8List? decodePhoto(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      final clean =
          base64Str.contains(',') ? base64Str.split(',').last : base64Str;
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }
}
