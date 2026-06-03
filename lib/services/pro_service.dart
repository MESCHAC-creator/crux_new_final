import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

class ProService {
  static final ProService _instance = ProService._internal();
  factory ProService() => _instance;
  ProService._internal();

  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  /// Check if user has active Pro subscription
  Future<bool> isPro(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      final isPro = data['isPro'] == true;
      if (!isPro) return false;
      final expiry = (data['proExpiry'] as Timestamp?)?.toDate();
      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Stream Pro status for real-time updates
  Stream<bool> proStream(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snap) {
      if (!snap.exists) return false;
      final data = snap.data()!;
      if (data['isPro'] != true) return false;
      final expiry = (data['proExpiry'] as Timestamp?)?.toDate();
      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    });
  }

  /// Create PayDunya payment and open URL
  Future<void> startPayment({
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    final callable = _functions.httpsCallable('createPayment');
    final result = await callable.call({
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail ?? '',
    });
    final paymentUrl = result.data['paymentUrl'] as String?;
    if (paymentUrl != null) {
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
