import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

class ProService {
  static final ProService _instance = ProService._internal();
  factory ProService() => _instance;
  ProService._internal();

  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  static const _priceXof = 25000;

  Future<bool> checkProStatus(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      if (data['isPro'] != true) return false;

      final expiresAt = data['proExpiresAt'];
      DateTime? expiry;
      if (expiresAt is Timestamp) {
        expiry = expiresAt.toDate();
      } else if (expiresAt is String) {
        expiry = DateTime.tryParse(expiresAt);
      } else if (expiresAt is int) {
        expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt);
      }

      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Stream<bool> proStream(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snap) {
      if (!snap.exists) return false;
      final data = snap.data()!;
      if (data['isPro'] != true) return false;

      final expiresAt = data['proExpiresAt'];
      DateTime? expiry;
      if (expiresAt is Timestamp) {
        expiry = expiresAt.toDate();
      } else if (expiresAt is String) {
        expiry = DateTime.tryParse(expiresAt);
      } else if (expiresAt is int) {
        expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt);
      }

      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    });
  }

  Future<Map<String, dynamic>?> startPayment({
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Vous devez être connecté pour souscrire.');
    }
    if (user.uid != userId) {
      throw Exception('Action non autorisée.');
    }

    try {
      final result = await _functions.httpsCallable('createPayment').call({
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final invoiceUrl = data['invoice_url'] as String?;

      if (invoiceUrl != null && invoiceUrl.isNotEmpty) {
        final uri = Uri.parse(invoiceUrl);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      }

      return data;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erreur de paiement');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _activateProLegacy(String userId) async {
    final proExpiresAt = DateTime.now().add(const Duration(days: 30));
    await _db.collection('users').doc(userId).set({
      'isPro': true,
      'proExpiresAt': Timestamp.fromDate(proExpiresAt),
      'proActivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int get priceXof => _priceXof;
}
