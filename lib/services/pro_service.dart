import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class ProService {
  static final ProService _instance = ProService._internal();
  factory ProService() => _instance;
  ProService._internal();

  final _db = FirebaseFirestore.instance;

  static const _paymentUrl = 'https://pay.djamo.com/qxmvj';
  static const _priceXof = 25000;

  Future<bool> isPro(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      if (data['isPro'] != true) return false;
      final expiry = DateTime.tryParse(data['proExpiry'] ?? '');
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
      final expiry = DateTime.tryParse(data['proExpiry'] ?? '');
      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    });
  }

  /// Opens the Djamo payment link directly
  Future<void> startPayment({
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    final uri = Uri.parse(_paymentUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  /// Called manually by admin or after payment confirmation to activate Pro
  Future<void> activatePro(String userId) async {
    final proExpiry = DateTime.now().add(const Duration(days: 30));
    await _db.collection('users').doc(userId).set({
      'isPro': true,
      'proExpiry': proExpiry.toIso8601String(),
      'lastPayment': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  int get priceXof => _priceXof;
  String get paymentUrl => _paymentUrl;
}
