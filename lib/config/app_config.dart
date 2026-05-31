import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Config {
  static final _secureStorage = const FlutterSecureStorage();

  // Getters für Agora
  static String get agoraAppId => dotenv.env['AGORA_APP_ID'] ?? '';
  static String get agoraAppCertificate => dotenv.env['AGORA_APP_CERTIFICATE'] ?? '';
  static String get agoraTokenUrl => dotenv.env['AGORA_TOKEN_URL'] ?? '';

  // Getters für Firebase
  static String get firebaseProjectId => dotenv.env['FIREBASE_PROJECT_ID'] ?? 'crux-8aa85';

  // Environment
  static String get environment => dotenv.env['ENVIRONMENT'] ?? 'development';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  // Secure Storage (für tokens, etc)
  static Future<void> setSecureToken(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  static Future<String?> getSecureToken(String key) async {
    return await _secureStorage.read(key: key);
  }

  static Future<void> deleteSecureToken(String key) async {
    await _secureStorage.delete(key: key);
  }
}
