import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// Service de gestion de la bande passante pour optimiser la qualité vidéo.
///
/// Ce service surveille l'utilisation de la bande passante et ajuste
/// automatiquement la qualité vidéo pour garantir une expérience fluide.
class BandwidthService {
  BandwidthService._();

  static final BandwidthService instance = BandwidthService._();

  final _logger = Logger();
  
  // État de la bande passante
  double _currentBandwidth = 0.0; // en Mbps
  int _totalBytesTransferred = 0;
  DateTime? _sessionStartTime;
  
  // Configuration
  bool _dataSaverMode = false;
  bool _autoQualityAdjustment = true;
  VideoQuality _currentVideoQuality = VideoQuality.hd;
  
  // Callback pour les mises à jour de bande passante
  Function(double)? _onBandwidthUpdate;

  // Préférences utilisateur
  static const String _dataSaverKey = 'crux_data_saver';
  static const String _autoQualityKey = 'crux_auto_quality';

  // Getters
  double get currentBandwidth => _currentBandwidth;
  VideoQuality get currentVideoQuality => _currentVideoQuality;
  bool get dataSaverMode => _dataSaverMode;
  bool get autoQualityAdjustment => _autoQualityAdjustment;

  BandwidthService({Function(double)? onBandwidthUpdate}) {
    _onBandwidthUpdate = onBandwidthUpdate;
  }

  /// Initialise le service de bande passante
  Future<void> initialize() async {
    await _loadPreferences();
    _sessionStartTime = DateTime.now();
    _logger.i('BandwidthService initialized - Data Saver: $_dataSaverMode, Auto Quality: $_autoQualityAdjustment');
  }

  /// Charge les préférences utilisateur
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dataSaverMode = prefs.getBool(_dataSaverKey) ?? false;
      _autoQualityAdjustment = prefs.getBool(_autoQualityKey) ?? true;
    } catch (e) {
      _logger.e('Failed to load bandwidth preferences', error: e);
    }
  }

  /// Sauvegarde les préférences utilisateur
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dataSaverKey, _dataSaverMode);
      await prefs.setBool(_autoQualityKey, _autoQualityAdjustment);
    } catch (e) {
      _logger.e('Failed to save bandwidth preferences', error: e);
    }
  }

  /// Active/désactive le mode économie de données
  Future<void> setDataSaverMode(bool enabled) async {
    if (_dataSaverMode == enabled) return;

    _dataSaverMode = enabled;
    await _savePreferences();

    if (enabled) {
      _currentVideoQuality = VideoQuality.low;
      _logger.i('Data saver mode enabled');
    } else {
      _adjustQualityBasedOnBandwidth();
      _logger.i('Data saver mode disabled');
    }

    _applyQualityChange();
  }

  /// Active/désactive l'ajustement automatique de qualité
  Future<void> setAutoQualityAdjustment(bool enabled) async {
    _autoQualityAdjustment = enabled;
    await _savePreferences();
    _logger.i('Auto quality adjustment: $_autoQualityAdjustment');
  }

  /// Met à jour la bande passante actuelle
  void updateBandwidth(double bandwidthMbps) {
    _currentBandwidth = bandwidthMbps;
    _onBandwidthUpdate?.call(_currentBandwidth);
    
    if (_autoQualityAdjustment && !_dataSaverMode) {
      _adjustQualityBasedOnBandwidth();
    }
  }

  /// Ajuste la qualité vidéo en fonction de la bande passante
  void _adjustQualityBasedOnBandwidth() {
    VideoQuality newQuality;
    
    if (_currentBandwidth < 1.0) {
      newQuality = VideoQuality.low;
    } else if (_currentBandwidth < 3.0) {
      newQuality = VideoQuality.medium;
    } else if (_currentBandwidth < 5.0) {
      newQuality = VideoQuality.hd;
    } else {
      newQuality = VideoQuality.fullHd;
    }

    if (newQuality != _currentVideoQuality) {
      _currentVideoQuality = newQuality;
      _logger.i('Quality adjusted to ${_currentVideoQuality.name} (bandwidth: ${_currentBandwidth.toStringAsFixed(2)} Mbps)');
      _applyQualityChange();
    }
  }

  /// Applique le changement de qualité
  void _applyQualityChange() {
    // Ici, vous pouvez émettre un événement ou notifier les autres services
    // que la qualité vidéo a changé
  }

  /// Enregistre le transfert de données
  void recordDataTransfer(int bytes) {
    _totalBytesTransferred += bytes;
  }

  /// Obtient les statistiques d'utilisation
  Map<String, dynamic> getUsageStatistics() {
    if (_sessionStartTime == null) {
      return {};
    }

    final duration = DateTime.now().difference(_sessionStartTime!);
    final durationInMinutes = duration.inMinutes + duration.inSeconds / 60.0;
    final dataUsedMB = _totalBytesTransferred / (1024 * 1024);
    final averageMbps = durationInMinutes > 0 
        ? (dataUsedMB * 8) / (durationInMinutes * 60) 
        : 0.0;

    return {
      'totalBytes': _totalBytesTransferred,
      'totalMB': dataUsedMB.toStringAsFixed(2),
      'durationMinutes': durationInMinutes.toStringAsFixed(1),
      'averageMbps': averageMbps.toStringAsFixed(2),
      'currentQuality': _currentVideoQuality.name,
      'dataSaverMode': _dataSaverMode,
      'estimatedRemainingBandwidth': _currentBandwidth,
    };
  }

  /// Convertit la qualité en paramètres LiveKit
  Map<String, dynamic> getLiveKitVideoParameters() {
    switch (_currentVideoQuality) {
      case VideoQuality.low:
        return {
          'width': 640,
          'height': 360,
          'maxBitrate': 300_000,
          'maxFramerate': 15,
        };
      case VideoQuality.medium:
        return {
          'width': 854,
          'height': 480,
          'maxBitrate': 500_000,
          'maxFramerate': 24,
        };
      case VideoQuality.hd:
        return {
          'width': 1280,
          'height': 720,
          'maxBitrate': 1_500_000,
          'maxFramerate': 30,
        };
      case VideoQuality.fullHd:
        return {
          'width': 1920,
          'height': 1080,
          'maxBitrate': 3_000_000,
          'maxFramerate': 30,
        };
    }
  }

  /// Réinitialise les statistiques de session
  void resetSessionStatistics() {
    _totalBytesTransferred = 0;
    _sessionStartTime = DateTime.now();
    _logger.i('Session statistics reset');
  }

  void dispose() {
    // Nettoyage si nécessaire
  }
}

enum VideoQuality {
  low,
  medium,
  hd,
  fullHd,
}