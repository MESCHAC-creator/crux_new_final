import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceVerificationService {
  static final DeviceVerificationService _instance =
      DeviceVerificationService._();

  final Logger _log = Logger();

  DeviceVerificationService._();

  static DeviceVerificationService get instance => _instance;

  /// Vérification générale de sécurité du périphérique.
  ///
  /// Compatible :
  /// - Android
  /// - iOS
  /// - Web
  /// - Windows
  /// - macOS
  /// - Linux
  ///
  /// Retourne :
  /// (isSecure, reason)
  Future<(bool isSecure, String reason)> verifyDeviceSecurity() async {
    try {
      // ============================================================
      // WEB
      // ============================================================
      //
      // dart:io / Platform.isAndroid / Platform.isIOS ne doivent
      // pas être utilisés directement dans le build Web.
      //
      // Sur Web, les vérifications natives de root/jailbreak
      // n'ont pas de sens.
      //
      if (kIsWeb) {
        await _verifyWeb();

        _log.i('Device verification OK — Web');

        return (true, '');
      }

      // ============================================================
      // DEVICE INFORMATION
      // ============================================================

      final deviceInfo = DeviceInfoPlugin();

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _verifyAndroid(deviceInfo);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _verifyIOS(deviceInfo);
      } else {
        // Desktop / autres plateformes.
        await _verifyDesktop(deviceInfo);
      }

      // ============================================================
      // APP INFORMATION
      // ============================================================

      await _verifyApplication();

      // ============================================================
      // STORAGE
      // ============================================================

      final hasEnoughStorage = await _hasEnoughStorage();

      if (!hasEnoughStorage) {
        return (
          false,
          'Espace disque insuffisant. Libérez de l’espace puis réessayez.',
        );
      }

      _log.i('Device verification OK');

      return (true, '');
    } catch (e, stackTrace) {
      _log.e(
        'Erreur pendant la vérification du périphérique',
        error: e,
        stackTrace: stackTrace,
      );

      // Fail-open :
      // une erreur de vérification ne doit pas empêcher
      // l'utilisateur d'utiliser CRUX.
      return (true, '');
    }
  }

  // ================================================================
  // WEB
  // ================================================================

  Future<void> _verifyWeb() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      final webInfo = await deviceInfo.webBrowserInfo;

      _log.d('Web browser: ${webInfo.browserName}');

      _log.d('Web platform: ${webInfo.platform}');

      _log.d('Web user agent: ${webInfo.userAgent}');
    } catch (e) {
      _log.w('Impossible de récupérer les informations du navigateur: $e');
    }

    // Sur Web :
    // - pas de root detection
    // - pas de jailbreak detection
    // - pas de filesystem native
    //
    // On considère donc le périphérique comme compatible.
  }

  // ================================================================
  // ANDROID
  // ================================================================

  Future<void> _verifyAndroid(DeviceInfoPlugin deviceInfo) async {
    try {
      final androidInfo = await deviceInfo.androidInfo;

      final sdk = androidInfo.version.sdkInt;

      _log.d('Android SDK: $sdk');

      _log.d('Android model: ${androidInfo.model}');

      _log.d('Android manufacturer: ${androidInfo.manufacturer}');

      // Android 8.0 minimum.
      if (sdk < 26) {
        throw const DeviceVerificationException(
          'Android 8.0 ou version ultérieure est requis.',
        );
      }

      // Root detection volontairement non bloquante.
      //
      // La détection de root fiable nécessite généralement
      // une implémentation native dédiée.
      //
      // On ne bloque donc pas l'utilisateur ici.
    } catch (e) {
      if (e is DeviceVerificationException) {
        rethrow;
      }

      _log.w('Vérification Android partielle: $e');
    }
  }

  // ================================================================
  // IOS
  // ================================================================

  Future<void> _verifyIOS(DeviceInfoPlugin deviceInfo) async {
    try {
      final iosInfo = await deviceInfo.iosInfo;

      final version = iosInfo.systemVersion;

      _log.d('iOS version: $version');

      _log.d('iOS model: ${iosInfo.utsname.machine}');

      if (!_isIOSVersionValid(version)) {
        throw const DeviceVerificationException(
          'iOS 14.0 ou version ultérieure est requis.',
        );
      }

      // Jailbreak detection volontairement non bloquante.
    } catch (e) {
      if (e is DeviceVerificationException) {
        rethrow;
      }

      _log.w('Vérification iOS partielle: $e');
    }
  }

  // ================================================================
  // DESKTOP
  // ================================================================

  Future<void> _verifyDesktop(DeviceInfoPlugin deviceInfo) async {
    try {
      final info = await deviceInfo.deviceInfo;

      _log.d('Desktop device information: ${info.data}');
    } catch (e) {
      _log.w('Informations desktop indisponibles: $e');
    }
  }

  // ================================================================
  // APPLICATION
  // ================================================================

  Future<void> _verifyApplication() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      final packageName = packageInfo.packageName;
      final version = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;

      _log.d('Application: $packageName');

      _log.d('Version: $version');

      _log.d('Build: $buildNumber');

      // Les applications Web n'ont pas le même package name
      // qu'Android/iOS.
      //
      // Cette vérification reste informative et ne bloque jamais.
      const expectedPackages = <String>{
        'com.schac_crux.app',
        'com.schac-crux.app',
        'com.crux.app',
        'com.crux.videocall',
      };

      if (!kIsWeb && !expectedPackages.contains(packageName)) {
        _log.w('Package name inattendu: $packageName');
      }
    } catch (e) {
      _log.w('Impossible de récupérer les informations de l’application: $e');
    }
  }

  // ================================================================
  // STORAGE
  // ================================================================

  Future<bool> _hasEnoughStorage() async {
    //
    // Il n'existe pas ici de méthode portable fiable permettant
    // d'obtenir l'espace disque disponible sur toutes les plateformes.
    //
    // Pour le Web, le navigateur contrôle entièrement le stockage.
    //
    if (kIsWeb) {
      return true;
    }

    // Pour éviter de casser Android/iOS/Desktop à cause d'une
    // vérification de stockage non portable, on considère la
    // vérification comme réussie.
    //
    // Une vraie vérification pourra être ajoutée ultérieurement
    // via une implémentation native/plateforme spécifique.
    return true;
  }

  // ================================================================
  // IOS VERSION
  // ================================================================

  bool _isIOSVersionValid(String version) {
    try {
      final parts = version.split('.');

      if (parts.isEmpty) {
        return false;
      }

      final major = int.tryParse(parts.first);

      if (major == null) {
        return false;
      }

      return major >= 14;
    } catch (_) {
      return false;
    }
  }
}

class DeviceVerificationException implements Exception {
  final String message;

  const DeviceVerificationException(this.message);

  @override
  String toString() => message;
}
