import 'dart:async';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart' as crux;

/// Niveaux de qualité vidéo (déclaré HORS de la classe, sinon erreur de compilation).
enum CruxVideoQuality {
  low(360, 15, 0.3),      // 360p @ 15fps, ~0.3 Mbps
  medium(480, 24, 0.5),   // 480p @ 24fps, ~0.5 Mbps
  high(720, 30, 1.5),     // 720p @ 30fps, ~1.5 Mbps
  hd(1080, 30, 3.0),      // 1080p @ 30fps, ~3.0 Mbps
  fullHd(1080, 60, 5.0);  // 1080p @ 60fps, ~5.0 Mbps

  final int resolution;
  final int frameRate;
  final double estimatedBandwidth;

  const CruxVideoQuality(this.resolution, this.frameRate, this.estimatedBandwidth);

  String get label {
    switch (this) {
      case CruxVideoQuality.low:
        return 'Basse (360p)';
      case CruxVideoQuality.medium:
        return 'Moyenne (480p)';
      case CruxVideoQuality.high:
        return 'Haute (720p)';
      case CruxVideoQuality.hd:
        return 'HD (1080p)';
      case CruxVideoQuality.fullHd:
        return 'Full HD (1080p 60fps)';
    }
  }
}

/// Service d'optimisation de la bande passante avec mode économie de données.
///
/// Ce service adapte dynamiquement la qualité vidéo en fonction des conditions
/// réseau et des préférences utilisateur pour réduire la consommation de données.
class BandwidthService {
  BandwidthService._();

  static final BandwidthService instance = BandwidthService._();

  final crux.Logger _logger = crux.logger;

  // Mode économie de données
  bool _dataSaverMode = false;
  bool _autoQualityAdjustment = true;

  // Surveillance de la bande passante
  double _currentBandwidth = 0.0; // en Mbps
  Timer? _bandwidthMonitor;
  static const Duration _bandwidthCheckInterval = Duration(seconds: 10);

  // Qualité vidéo actuelle
  CruxVideoQuality _currentVideoQuality = CruxVideoQuality.high;
  CruxVideoQuality _targetVideoQuality = CruxVideoQuality.high;

  // Statistiques
  int _totalBytesTransferred = 0;
  DateTime _sessionStartTime = DateTime.now();

  // Seuils de bande passante (Mbps)
  static const double _lowBandwidthThreshold = 0.5;    // < 0.5 Mbps
  static const double _mediumBandwidthThreshold = 1.5; // < 1.5 Mbps
  static const double _highBandwidthThreshold = 3.0;   // >= 3.0 Mbps

  // Callbacks
  Function(CruxVideoQuality)? _onQualityChanged;
  Function(double)? _onBandwidthUpdate;

  // Getters
  bool get dataSaverMode => _dataSaverMode;
  bool get autoQualityAdjustment => _autoQualityAdjustment;
  double get currentBandwidth => _currentBandwidth;
  CruxVideoQuality get currentVideoQuality => _currentVideoQuality;
  int get totalBytesTransferred => _totalBytesTransferred;
  Duration get sessionDuration => DateTime.now().difference(_sessionStartTime);

  /// Initialise le service
  Future<void> initialize({
    Function(CruxVideoQuality)? onQualityChanged,
    Function(double)? onBandwidthUpdate,
  }) async {
    _onQualityChanged = onQualityChanged;
    _onBandwidthUpdate = onBandwidthUpdate;

    await _loadPreferences();
    _startBandwidthMonitoring();

    _logger.i('BandwidthService initialized - Data Saver: dataSaverMode,AutoQuality:_dataSaverMode, Auto Quality:d​ataSaverMode,AutoQuality:_autoQualityAdjustment');
  }

  /// Charge les préférences utilisateur
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dataSaverMode = prefs.getBool('crux_data_saver') ?? false;
      _autoQualityAdjustment = prefs.getBool('crux_auto_quality') ?? true;

      // Appliquer le mode économie de données
      if (_dataSaverMode) {
 _targetVideoQuality = CruxVideoQuality.low;
      }
    } catch (e) {
      _logger.e('Failed to load bandwidth preferences', error: e);
    }
  }

  /// Sauvegarde les préférences utilisateur
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('crux_data_saver', _dataSaverMode);
      await prefs.setBool('crux_auto_quality', _autoQualityAdjustment);
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
      _targetVideoQuality = CruxVideoQuality.low;
      _logger.i('Data saver mode enabled');
    } else {
      _adjustQualityBasedOnBandwidth();
      _logger.i('Data saver mode disabled');
    }

    _applyQualityChange();
  }

  /// Active/désactive l'ajustement automatique de qualité
  Future<void> setAutoQualityAdjustment(bool enabled) async {
    if (_autoQualityAdjustment == enabled) return;

    _autoQualityAdjustment = enabled;
    await _savePreferences();

    if (enabled) {
      _adjustQualityBasedOnBandwidth();
      _logger.i('Auto quality adjustment enabled');
    } else {
      _logger.i('Auto quality adjustment disabled');
    }
  }

  /// Définit manuellement la qualité vidéo
  void setVideoQuality(CruxVideoQuality quality) {
    if (_dataSaverMode && quality != CruxVideoQuality.low) {
      _logger.w('Cannot set high quality in data saver mode');
      return;
    }

    _targetVideoQuality = quality;
    _autoQualityAdjustment = false;
    _applyQualityChange();
  }

  /// Démarre la surveillance de la bande passante
  void _startBandwidthMonitoring() {
    _bandwidthMonitor = Timer.periodic(_bandwidthCheckInterval, (_) {
      _updateBandwidthEstimate();
    });
  }

  /// Met à jour l'estimation de bande passante
  void _updateBandwidthEstimate() {
    // En production, utiliser les statistiques réelles de LiveKit
    // Ici, nous simulons une estimation basée sur les bytes transférés

    final bytesSinceLastCheck = _totalBytesTransferred;
    final estimatedBandwidth = (bytesSinceLastCheck * 8) /
        (_bandwidthCheckInterval.inSeconds * 1000000);

    _currentBandwidth = estimatedBandwidth;
    _onBandwidthUpdate?.call(_currentBandwidth);

    if (_autoQualityAdjustment && !_dataSaverMode) {
      _adjustQualityBasedOnBandwidth();
    }

    _logger.d('Bandwidth estimate: ${_currentBandwidth.toStringAsFixed(2)} Mbps');
  }

  /// Ajuste la qualité en fonction de la bande passante
  void _adjustQualityBasedOnBandwidth() {
    CruxVideoQuality newQuality;

    if (_currentBandwidth < _lowBandwidthThreshold) {
      newQuality = CruxVideoQuality.low;
    } else if (_currentBandwidth < _mediumBandwidthThreshold) {
      newQuality = CruxVideoQuality.medium;
    } else if (_currentBandwidth < _highBandwidthThreshold) {
      newQuality = CruxVideoQuality.high;
    } else {
      newQuality = CruxVideoQuality.hd;
    }

    if (newQuality != _targetVideoQuality) {
      _targetVideoQuality = newQuality;
      _applyQualityChange();
      _logger.i('Quality adjusted to ${newQuality.label} based on bandwidth');
    }
  }

  /// Applique le changement de qualité
  void _applyQualityChange() {
    if (_currentVideoQuality == _targetVideoQuality) return;

    _currentVideoQuality = _targetVideoQuality;
    _onQualityChanged?.call(_currentVideoQuality);
    _logger.i('Video quality changed to ${_currentVideoQuality.label}');
  }

  /// Met à jour les statistiques de transfert de données
  void updateTransferStats(int bytesTransferred) {
    _totalBytesTransferred += bytesTransferred;
  }

  /// Réinitialise les statistiques de session
  void resetSessionStats() {
    _totalBytesTransferred = 0;
    _sessionStartTime = DateTime.now();
    _logger.d('Session stats reset');
  }

  /// Obtient des statistiques détaillées sur la consommation de données
  Map<String, dynamic> getDataUsageStats() {
    final durationInMinutes = sessionDuration.inMinutes.toDouble();
    final dataUsedMB = _totalBytesTransferred / (1024 * 1024);
    final averageMbps = durationInMinutes > 0
        ? (dataUsedMB * 8) / (durationInMinutes * 60)
        : 0.0;

    return {
      'totalBytes': _totalBytesTransferred,
      'totalMB': dataUsedMB.toStringAsFixed(2),
      'durationMinutes': durationInMinutes.toStringAsFixed(1),
      'averageMbps': averageMbps.toStringAsFixed(2),
      'currentQuality': _currentVideoQuality.label,
      'dataSaverMode': _dataSaverMode,
      'estimatedRemainingBandwidth': _currentBandwidth,
    };
  }

  /// Convertit la qualité en paramètres LiveKit
  Map<String, dynamic> getLiveKitVideoParameters() {
    switch (_currentVideoQuality) {
      case CruxVideoQuality.low:
        return {
          'width': 640,
          'height': 360,
          'maxBitrate': 300000,
          'maxFramerate': 15,
        };
      case CruxVideoQuality.medium:
        return {
          'width': 854,
          'height': 480,
          'maxBitrate': 500000,
          'maxFramerate': 24,
        };
      case CruxVideoQuality.high:
        return {
          'width': 1280,
          'height': 720,
          'maxBitrate': 1500000,
          'maxFramerate': 30,
        };
      case CruxVideoQuality.hd:
        return {
          'width': 1920,
          'height': 1080,
          'maxBitrate': 3000000,
          'maxFramerate': 30,
        };
      case CruxVideoQuality.fullHd:
        return {
          'width': 1920,
          'height': 1080,
          'maxBitrate': 5000000,
          'maxFramerate': 60,
        };
    }
  }

  /// Obtient la qualité recommandée pour l'abonnement distant
  CruxVideoQuality getSubscriptionQuality() {
    if (_dataSaverMode) return CruxVideoQuality.low;

    // Pour l'abonnement, on peut utiliser une qualité légèrement inférieure
    // pour économiser la bande passante entrante
    switch (_currentVideoQuality) {
      case CruxVideoQuality.fullHd:
        return CruxVideoQuality.hd;
      case CruxVideoQuality.hd:
        return CruxVideoQuality.high;
      default:
        return _currentVideoQuality;
    }
  }

  /// Nettoie les ressources
  void dispose() {
    _bandwidthMonitor?.cancel();
    _logger.i('BandwidthService disposed');
  }
}
