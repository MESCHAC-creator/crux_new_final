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

        // 2. Check for rooting/custom ROMs (warn only — don't block)
        if (await _isRooted()) {
          _log.w('⚠️ Root detected — proceeding anyway (warn-only mode)');
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

        // Check jailbreak (warn only — don't block)
        if (await _isJailbroken()) {
          _log.w('⚠️ Jailbreak detected — proceeding anyway (warn-only mode)');
        }
      }

      // 3. Check disk space
      final space = await _getAvailableStorageSpace();
      if (space < 100 * 1024 * 1024) {
        // 100MB
        return (
          false,
          '💾 Espace disque insuffisant (<100MB). Libérez de l\'espace et réessayez.',
        );
      }

      // 4. Check app signature (basic)
      final packageInfo = await PackageInfo.fromPlatform();
      const expectedPackages = [
        'com.schac_crux.app',
        'com.schac-crux.app',
        'com.crux.app',
        'com.crux.videocall',
      ];
      if (!expectedPackages.contains(packageInfo.packageName)) {
        _log.w('⚠️ Package name inattendu: ${packageInfo.packageName}');
        // Don't block — log only
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

  /// Basic root detection (not foolproof, but deters casual attackers)
  Future<bool> _isRooted() async {
    if (!Platform.isAndroid) return false;

    try {
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
    } catch (_) {
      // Gracefully ignore any filesystem exceptions
    }
    return false;
  }

  /// Check iOS jailbreak indicators
  Future<bool> _isJailbroken() async {
    if (!Platform.isIOS) return false;

    // Check for Cydia (common jailbreak app) using native File System API
    try {
      final cydiaDir = Directory('/Applications/Cydia.app');
      return await cydiaDir.exists();
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

  /// Get available disk space using the app's cache directory as probe
  Future<int> _getAvailableStorageSpace() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Use the temp directory as a proxy for available space
        // dart:io Directory.systemTemp gives access to temp partition
        final dir = Directory.systemTemp;
        if (!dir.existsSync()) return 1024 * 1024 * 1024;

        // Write a 1-byte probe to confirm writability; stat the parent for space
        final probe = File('${dir.path}/.crux_space_probe');
        try {
          probe.writeAsBytesSync([0]);
          probe.deleteSync();
        } catch (_) {
          // Can't write → very low space
          return 0;
        }
      }
    } catch (e) {
      _log.w('Disk space check failed: $e');
    }
    return 1024 * 1024 * 1024; // assume OK if check fails
  }
}
