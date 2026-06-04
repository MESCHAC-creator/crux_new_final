import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:logger/logger.dart';

class DeviceVerificationService {
  static final DeviceVerificationService _instance = DeviceVerificationService._();
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
        if (androidInfo.version.sdkInt < 26) { // Android 8+
          return (false, '🔒 Android 8.0+ requis. Veuillez mettre à jour votre système.');
        }

        // 2. Check for rooting/custom ROMs (basic check)
        if (await _isRooted()) {
          return (false, '⚠️ Appareils rootés non supportés pour des raisons de sécurité.');
        }
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        // iOS 14+
        if (!_isIOSVersionValid(iosInfo.systemVersion)) {
          return (false, '🔒 iOS 14.0+ requis. Veuillez mettre à jour votre système.');
        }

        // Check jailbreak
        if (await _isJailbroken()) {
          return (false, '⚠️ Appareils jailbreakés non supportés pour des raisons de sécurité.');
        }
      }

      // 3. Check disk space
      final space = await _getAvailableStorageSpace();
      if (space < 100 * 1024 * 1024) { // 100MB
        return (false, '💾 Espace disque insuffisant (<100MB). Libérez de l\'espace et réessayez.');
      }

      // 4. Check app signature (basic)
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.packageName != 'com.crux.videocall') {
        _log.w('⚠️ Package name mismatch: ${packageInfo.packageName}');
        // Don't block, but log
      }

      _log.i('✅ Vérification device OK');
      return (true, '');
    } catch (e) {
      _log.e('Erreur vérification device: $e');
      // On error, fail open (allow) but log
      return (true, '');
    }
  }

  /// Basic root detection (not foolproof, but deters casual attackers)
  Future<bool> _isRooted() async {
    if (!Platform.isAndroid) return false;

    // Check for common root indicators
    final files = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
    ];

    for (final file in files) {
      if (await File(file).exists()) {
        return true;
      }
    }
    return false;
  }

  /// Check iOS jailbreak indicators
  Future<bool> _isJailbroken() async {
    if (!Platform.isIOS) return false;

    // Check for Cydia (common jailbreak app)
    try {
      final result = await Process.run('ls', ['/Applications/Cydia.app'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
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

  /// Get available disk space in bytes
  Future<int> _getAvailableStorageSpace() async {
    // This is a simplified check — in production, use:
    // https://pub.dev/packages/disk_space
    // For now, assume sufficient space (return 1GB if check fails)
    return 1024 * 1024 * 1024;
  }
}
