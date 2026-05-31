import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final _logger = Logger();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> initialize() async {
    try {
      // Request permission
      await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carryForwardToken: true,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Get token
      String? token = await _firebaseMessaging.getToken();
      _logger.i('✅ FCM Token: $token');

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.i('📨 Message reçu au premier plan');
        _handleMessage(message);
      });

      // Handle background messages
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logger.i('📨 Message ouvert au arrière-plan');
        _handleMessage(message);
      });

      _logger.i('✅ Service de notifications initialisé');
    } catch (e) {
      _logger.e('❌ Erreur initialisation notifications: $e');
    }
  }

  void _handleMessage(RemoteMessage message) {
    _logger.i('📬 Notification: ${message.notification?.title}');
    _logger.i('📝 Message: ${message.notification?.body}');
  }

  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      _logger.e('❌ Erreur récupération token: $e');
      return null;
    }
  }
}