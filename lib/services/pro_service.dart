import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ProService {
  static final ProService _instance = ProService._internal();
  factory ProService() => _instance;
  ProService._internal();

  final _db = FirebaseFirestore.instance;

  static const _masterKey = 'Mt8Kupif-RFtT-Cchb-P2vq-p4T4DrZOLtV1';
  static const _privateKey = 'live_private_Ktf6Dx6nVicd5pEqRvSTbKBwNqB';
  static const _token = 'MXuDgF2N5Vd8LqIsTuzx';
  static const _baseUrl = 'https://app.paydunya.com/api/v1';

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

  /// Create PayDunya invoice directly and open payment URL
  Future<void> startPayment({
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    final payload = {
      'invoice': {
        'items': {
          'item_0': {
            'name': 'Crux Pro - Abonnement mensuel',
            'quantity': 1,
            'unit_price': '25000',
            'total_price': '25000',
            'description': 'Réunions illimitées pendant 30 jours',
          }
        },
        'taxes': {},
        'total_amount': 25000,
        'description': 'Crux Pro - 25 000 FCFA/mois',
      },
      'store': {'name': 'Crux Visioconférence'},
      'custom_data': {'userId': userId, 'userName': userName},
      'actions': {
        'cancel_url': 'https://crux-8aa85.web.app/payment-cancel',
        'return_url': 'https://crux-8aa85.web.app/payment-success',
        'callback_url': 'https://crux-8aa85.web.app/payment-webhook',
      },
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/checkout-invoice/create'),
      headers: {
        'PAYDUNYA-MASTER-KEY': _masterKey,
        'PAYDUNYA-PRIVATE-KEY': _privateKey,
        'PAYDUNYA-TOKEN': _token,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['response_code'] == '00') {
      final paymentUrl = data['response_text'] as String;
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Call after user returns from payment page to confirm and activate Pro
  Future<bool> confirmPayment(String invoiceToken, String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/checkout-invoice/confirm/$invoiceToken'),
        headers: {
          'PAYDUNYA-MASTER-KEY': _masterKey,
          'PAYDUNYA-PRIVATE-KEY': _privateKey,
          'PAYDUNYA-TOKEN': _token,
        },
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'completed') {
        final proExpiry = DateTime.now().add(const Duration(days: 30));
        await _db.collection('users').doc(userId).set({
          'isPro': true,
          'proExpiry': proExpiry.toIso8601String(),
          'lastPayment': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        return true;
      }
    } catch (_) {}
    return false;
  }
}
