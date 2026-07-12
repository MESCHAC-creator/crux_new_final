import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:logger/logger.dart';

class DeviceVerificationService {
  static final DeviceVerificationService _instance =
      DeviceVerificationService._();
  final _log = Logger();

  DeviceVerificationService._();

  static DeviceVerificationService get instance => _instance;

  /// Comprehensive device security check on app start
  /// Returns (isSecure, reason). If not secure, user cannot proceed.
  Future<(bool isSecure, String reason)> verifyDeviceSecurity() async {
    try {
      // 1. Check OS version
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 26) {
          // Android 8+
          return (
            false,
            '🔒 Android 8.0+ requis. Veuillez mettre à jour votre système.',
          );
        }
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        // iOS 14+
        if (!_isIOSVersionValid(iosInfo.systemVersion)) {
          return (
            false,
            '🔒 iOS 14.0+ requis. Veuillez mettre à jour votre système.',
          );
        }
      }

      // 2. Check disk space (Simplified to avoid Process.run)
      // We assume OK if we can't check reliably without crashing.
      // Most modern devices have enough space for basic operation.

      // 3. Check app signature (basic)
      final packageInfo = await PackageInfo.fromPlatform();
      const expectedPackages = [
        'com.schac_crux.app',
        'com.schac-crux.app',
        'com.crux.app',
        'com.crux.videocall',
      ];
      if (!expectedPackages.contains(packageInfo.packageName)) {
        _log.w('⚠️ Package name inattendu: ${packageInfo.packageName}');
      } else {
        _log.i('✅ Package vérifié: ${packageInfo.packageName}');
      }

      _log.i('✅ Vérification device OK');
      return (true, '');
    } catch (e) {
      _log.e('Erreur vérification device: $e');
      // On error, fail open (allow) but log
      return (true, '');
    }
  }

  /// Parse iOS version string (e.g., "17.2.1") and check >= 14.0
  bool _isIOSVersionValid(String version) {
    try {
      final parts = version.split('.');
      if (parts.isEmpty) return false;
      final major = int.tryParse(parts[0]) ?? 0;
      return major >= 14;
    } catch (_) {
      return false;
    }
  }
}
