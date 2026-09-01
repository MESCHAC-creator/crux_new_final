import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart' as crux;

/// Service d'accessibilité pour optimiser le support des lecteurs d'écran.
///
/// Ce service fournit des fonctionnalités pour améliorer l'accessibilité de l'application,
/// notamment pour les utilisateurs malvoyants utilisant des lecteurs d'écran.
class AccessibilityService {
  AccessibilityService._();

  static final AccessibilityService instance = AccessibilityService._();

  final _logger = crux.logger;
  final FlutterTts _tts = FlutterTts();

  // État de l'accessibilité
  bool _screenReaderEnabled = false;
  bool _highContrastMode = false;
  double _textScaleFactor = 1.0;
  bool _reducedMotion = false;
  bool _audioDescriptions = false;

  // Préférences utilisateur
  static const String _screenReaderEnabledKey = 'crux_screen_reader_enabled';
  static const String _highContrastModeKey = 'crux_high_contrast_mode';
  static const String _textScaleFactorKey = 'crux_text_scale_factor';
  static const String _reducedMotionKey = 'crux_reduced_motion';
  static const String _audioDescriptionsKey = 'crux_audio_descriptions';

  // Stream d'annonces pour les lecteurs d'écran
  final _announcementController = StreamController<String>.broadcast();
  Stream<String> get announcements => _announcementController.stream;

  // Getters
  bool get screenReaderEnabled => _screenReaderEnabled;
  bool get highContrastMode => _highContrastMode;
  double get textScaleFactor => _textScaleFactor;
  bool get reducedMotion => _reducedMotion;
  bool get audioDescriptions => _audioDescriptions;

  /// Initialise le service d'accessibilité
  Future<void> initialize() async {
    await _loadPreferences();
    await _initTts();
    _detectSystemAccessibility();
    
    _logger.i('AccessibilityService initialized - Screen Reader: $_screenReaderEnabled, High Contrast: $_highContrastMode');
  }

  /// Charge les préférences d'accessibilité
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _screenReaderEnabled = prefs.getBool(_screenReaderEnabledKey) ?? false;
      _highContrastMode = prefs.getBool(_highContrastModeKey) ?? false;
      _textScaleFactor = prefs.getDouble(_textScaleFactorKey) ?? 1.0;
      _reducedMotion = prefs.getBool(_reducedMotionKey) ?? false;
      _audioDescriptions = prefs.getBool(_audioDescriptionsKey) ?? false;
    } catch (e) {
      _logger.e('Failed to load accessibility preferences', error: e);
    }
  }

  /// Sauvegarde les préférences d'accessibilité
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_screenReaderEnabledKey, _screenReaderEnabled);
      await prefs.setBool(_highContrastModeKey, _highContrastMode);
      await prefs.setDouble(_textScaleFactorKey, _textScaleFactor);
      await prefs.setBool(_reducedMotionKey, _reducedMotion);
      await prefs.setBool(_audioDescriptionsKey, _audioDescriptions);
    } catch (e) {
      _logger.e('Failed to save accessibility preferences', error: e);
    }
  }

  /// Initialise le synthétiseur vocal
  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      _logger.e('Failed to initialize TTS', error: e);
    }
  }

  /// Détecte les paramètres d'accessibilité système
  void _detectSystemAccessibility() {
    // En production, utiliser des plugins comme accessibility_service
    // pour détecter les paramètres système réels
    // Ici, nous utilisons les préférences utilisateur
  }

  /// Active/désactive le mode lecteur d'écran
  Future<void> setScreenReaderEnabled(bool enabled) async {
    _screenReaderEnabled = enabled;
    await _savePreferences();
    _logger.i('Screen reader ${enabled ? "enabled" : "disabled"}');
  }

  /// Active/désactive le mode contraste élevé
  Future<void> setHighContrastMode(bool enabled) async {
    _highContrastMode = enabled;
    await _savePreferences();
    _logger.i('High contrast mode ${enabled ? "enabled" : "disabled"}');
  }

  /// Définit le facteur d'échelle du texte
  Future<void> setTextScaleFactor(double factor) async {
    _textScaleFactor = factor.clamp(1.0, 2.0);
    await _savePreferences();
    _logger.i('Text scale factor set to $_textScaleFactor');
  }

  /// Active/désactive le mouvement réduit
  Future<void> setReducedMotion(bool enabled) async {
    _reducedMotion = enabled;
    await _savePreferences();
    _logger.i('Reduced motion ${enabled ? "enabled" : "disabled"}');
  }

  /// Active/désactive les descriptions audio
  Future<void> setAudioDescriptions(bool enabled) async {
    _audioDescriptions = enabled;
    await _savePreferences();
    _logger.i('Audio descriptions ${enabled ? "enabled" : "disabled"}');
  }

  /// Annonce un message pour les lecteurs d'écran
  void announce(String message) {
    if (!_screenReaderEnabled) return;
    
    _announcementController.add(message);
    
    if (_audioDescriptions) {
      _speak(message);
    }
    
    _logger.d('Accessibility announcement: $message');
  }

  /// Prononce un message avec le synthétiseur vocal
  Future<void> _speak(String message) async {
    try {
      await _tts.speak(message);
    } catch (e) {
      _logger.e('Failed to speak message', error: e);
    }
  }

  /// Arrête la synthèse vocale en cours
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (e) {
      _logger.e('Failed to stop speaking', error: e);
    }
  }

  /// Génère une étiquette sémantique pour un widget
  String generateSemanticLabel({
    required String baseLabel,
    String? state,
    String? action,
    String? hint,
  }) {
    final parts = <String>[baseLabel];
    
    if (state != null && state.isNotEmpty) {
      parts.add(state);
    }
    
    if (action != null && action.isNotEmpty) {
      parts.add(action);
    }
    
    if (hint != null && hint.isNotEmpty) {
      parts.add(hint);
    }
    
    return parts.join(', ');
  }

  /// Crée un comportement sémantique personnalisé
  Semantics createSemantics({
    required String label,
    String? hint,
    String? value,
    bool? enabled,
    bool? checked,
    bool? selected,
    bool? toggled,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      enabled: enabled,
      checked: checked,
      selected: selected,
      toggled: toggled,
      button: onTap != null,
      link: onTap != null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// Obtient le thème accessible basé sur les préférences
  ThemeData getAccessibleTheme(ThemeData baseTheme) {
    if (!_highContrastMode) return baseTheme;

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: Colors.black,
        secondary: Colors.white,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      cardColor: Colors.white,
      dividerColor: Colors.black,
    );
  }

  /// Obtient la durée d'animation adaptée (mouvement réduit)
  Duration getAnimationDuration(Duration defaultDuration) {
    if (!_reducedMotion) return defaultDuration;
    return Duration.zero;
  }

  /// Obtient la courbe d'animation adaptée (mouvement réduit)
  Curve getAnimationCurve(Curve defaultCurve) {
    if (!_reducedMotion) return defaultCurve;
    return Curves.linear;
  }

  /// Vérifie si un élément doit recevoir le focus automatiquement
  bool shouldAutoFocus(bool screenReaderOnly) {
    return _screenReaderEnabled && screenReaderOnly;
  }

  /// Génère une description pour les participants
  String generateParticipantDescription({
    required String name,
    bool isMuted = false,
    bool isVideoOff = false,
    bool isHandRaised = false,
    bool isHost = false,
    bool isSpeaking = false,
  }) {
    final parts = <String>[name];
    
    if (isHost) parts.add('hôte');
    if (isSpeaking) parts.add('parle');
    if (isHandRaised) parts.add('main levée');
    if (isMuted) parts.add('micro coupé');
    if (isVideoOff) parts.add('caméra éteinte');
    
    return parts.join(', ');
  }

  /// Génère une description pour les contrôles de réunion
  String generateControlDescription({
    required String controlName,
    required bool isEnabled,
    String? additionalInfo,
  }) {
    final status = isEnabled ? 'activé' : 'désactivé';
    final parts = <String>['$controlName, $status'];
    
    if (additionalInfo != null && additionalInfo.isNotEmpty) {
      parts.add(additionalInfo);
    }
    
    return parts.join(', ');
  }

  /// Annule les changements importants (entrée/sortie de réunion, etc.)
  void announceImportantChange(String change) {
    announce('Changement important: $change');
  }

  /// Annule les erreurs
  void announceError(String error) {
    announce('Erreur: $error');
  }

  /// Annule les notifications
  void announceNotification(String notification) {
    announce('Notification: $notification');
  }

  /// Obtient des statistiques d'utilisation de l'accessibilité
  Map<String, dynamic> getAccessibilityStats() {
    return {
      'screenReaderEnabled': _screenReaderEnabled,
      'highContrastMode': _highContrastMode,
      'textScaleFactor': _textScaleFactor,
      'reducedMotion': _reducedMotion,
      'audioDescriptions': _audioDescriptions,
    };
  }

  /// Nettoie les ressources
  void dispose() {
    _announcementController.close();
    _tts.stop();
    _logger.i('AccessibilityService disposed');
  }
}

/// Extensions pour faciliter l'utilisation de l'accessibilité
extension AccessibilityWidgetExtension on Widget {
  /// Enveloppe le widget avec des propriétés d'accessibilité
  Widget withAccessibility({
    required String label,
    String? hint,
    String? value,
    bool? enabled,
    bool? checked,
    bool? selected,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      enabled: enabled,
      checked: checked,
      selected: selected,
      button: onTap != null,
      onTap: onTap,
      onLongPress: onLongPress,
      child: this,
    );
  }

  /// Ajoute une étiquette sémantique générée automatiquement
  Widget withSemanticLabel({
    required String baseLabel,
    String? state,
    String? action,
    String? hint,
  }) {
    final service = AccessibilityService.instance;
    final label = service.generateSemanticLabel(
      baseLabel: baseLabel,
      state: state,
      action: action,
      hint: hint,
    );
    
    return Semantics(
      label: label,
      child: this,
    );
  }
}