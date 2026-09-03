import 'dart:async';
import 'package:logger/logger.dart';

/// Niveaux de qualité vidéo pour CRUX
enum CruxVideoQuality {
  low(360, 15, 0.3),
  medium(480, 24, 0.5),
  high(720, 30, 1.5),
  hd(1080, 30, 3.0),
  fullHd(1080, 60, 5.0);

  final int resolution;
  final int frameRate;
  final double estimatedBandwidth;

  const CruxVideoQuality(this.resolution, this.frameRate, this.estimatedBandwidth);
}

class BandwidthService {
  static final BandwidthService _instance = BandwidthService._internal();

  final Logger _logger = Logger();

  factory BandwidthService() => _instance;
  BandwidthService._internal();

  bool _dataSaverMode = false;
  bool _autoQualityAdjustment = true;
  CruxVideoQuality _targetVideoQuality = CruxVideoQuality.medium;

  double _estimatedBandwidth = 5.0;
  Timer? _bandwidthMonitor;
  final Duration _bandwidthCheckInterval = const Duration(seconds: 5);

  Function(CruxVideoQuality)? _onQualityChanged;
  Function(double)? _onBandwidthUpdate;

  bool get dataSaverMode => _dataSaverMode;
  bool get autoQualityAdjustment => _autoQualityAdjustment;
  CruxVideoQuality get targetVideoQuality => _targetVideoQuality;
  double get estimatedBandwidth => _estimatedBandwidth;

  /// Initialise le service
  Future<void> initialize({
    Function(CruxVideoQuality)? onQualityChanged,
    Function(double)? onBandwidth,
  }) async {
    _onQualityChanged = onQualityChanged;
    _onBandwidthUpdate = onBandwidth;

    await _loadPreferences();
    _startBandwidthMonitoring();

    _logger.i('BandwidthService initialized - Data Saver: $_dataSaverMode, '
        'Auto Quality: $_autoQualityAdjustment');
  }

  /// Active/désactive le mode économie de données
  Future<void> setDataSaverMode(bool enabled) async {
    _dataSaverMode = enabled;
    await _savePreferences();

    if (enabled) {
      setVideoQuality(CruxVideoQuality.low);
      _logger.i('Data Saver mode enabled');
    }
  }

  /// Active/désactive l'ajustement auto de la qualité
  Future<void> setAutoQualityAdjustment(bool enabled) async {
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

  // ═══════════════════════════════════════════════════════
  //  SURVEILLANCE DE LA BANDE PASSANTE
  // ═══════════════════════════════════════════════════════

  /// Démarre la surveillance de la bande passante
  void _startBandwidthMonitoring() {
    _bandwidthMonitor?.cancel();
    _bandwidthMonitor = Timer.periodic(_bandwidthCheckInterval, (_) {
      _updateBandwidthEstimate();
    });
  }

  /// Met à jour l'estimation de la bande passante avec fallback simulé
  Future<void> _updateBandwidthEstimate() async {
    double measured = 0.0;
    double packetLoss = 0.0;
    double rttMs = 0.0;

    // ── Estimation simulée basée sur le temps écoulé ──
    // (Remplacement du WebRTC PeerConnection qui n'est plus accessible)
    try {
      // Simulation d'une variation de bande passante réaliste
      // Entre 1 Mbps et 10 Mbps avec légères fluctuations
      measured = 3.0 + (DateTime.now().millisecondsSinceEpoch % 5000) / 1000;

      // Simulation légère de perte de paquets
      packetLoss =
          DateTime.now().millisecondsSinceEpoch % 100 > 95 ? 0.5 : 0.0;

      // RTT simulé
      rttMs = 30 + (DateTime.now().millisecondsSinceEpoch % 50).toDouble();

      _estimatedBandwidth = measured;
      _onBandwidthUpdate?.call(_estimatedBandwidth);

      _logger.i(
          'Bandwidth: ${_estimatedBandwidth.toStringAsFixed(2)} Mbps | '
          'Loss: ${packetLoss.toStringAsFixed(2)}% | RTT: ${rttMs.toStringAsFixed(0)}ms');

      if (_autoQualityAdjustment) {
        _adjustQualityBasedOnBandwidth();
      }
    } catch (e) {
      _logger.e('Bandwidth estimation error: $e');
    }
  }

  /// Ajuste la qualité automatiquement en fonction de la bande passante
  void _adjustQualityBasedOnBandwidth() {
    final targetQuality = _qualityForBandwidth(_estimatedBandwidth);
    if (targetQuality != _targetVideoQuality) {
      setVideoQuality(targetQuality);
    }
  }

  /// Retourne la qualité recommandée pour une bande passante donnée
  CruxVideoQuality _qualityForBandwidth(double bandwidthMbps) {
    if (bandwidthMbps < 1.5) return CruxVideoQuality.low;
    if (bandwidthMbps < 3.0) return CruxVideoQuality.medium;
    return CruxVideoQuality.high;
  }

  /// Applique le changement de qualité
  void _applyQualityChange() {
    _onQualityChanged?.call(_targetVideoQuality);
    _logger.i('Video quality changed to: $_targetVideoQuality');
  }

  /// Charge les préférences
  Future<void> _loadPreferences() async {
    // Impl: charger depuis SharedPreferences ou localStorage
  }

  /// Sauvegarde les préférences
  Future<void> _savePreferences() async {
    // Impl: sauvegarder dans SharedPreferences ou localStorage
  }

  /// Libère les ressources
  void dispose() {
    _bandwidthMonitor?.cancel();
  }
}
