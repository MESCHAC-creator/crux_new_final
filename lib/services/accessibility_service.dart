import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../config/logger.dart';

/// Service de gestion de l'accessibilité
class AccessibilityService {
  static final AccessibilityService _instance = AccessibilityService._internal();

  factory AccessibilityService() => _instance;
  AccessibilityService._internal();

  bool _highContrastMode = false;
  bool _reducedMotion = false;
  bool _screenReaderEnabled = false;

  bool get highContrastMode => _highContrastMode;
  bool get reducedMotion => _reducedMotion;
  bool get screenReaderEnabled => _screenReaderEnabled;

  /// Initialise le service d'accessibilité
  Future<void> initialize() async {
    try {
      _highContrastMode = false;
      _reducedMotion = false;
      _screenReaderEnabled = false;

      crux.logger.i('AccessibilityService initialized');
    } catch (e) {
      crux.logger.e('Failed to initialize accessibility: $e');
    }
  }

  /// Active/désactive le mode contraste élevé
  void setHighContrastMode(bool enabled) {
    _highContrastMode = enabled;
    crux.logger.i('High contrast mode: $_highContrastMode');
  }

  /// Active/désactive le mouvement réduit
  void setReducedMotion(bool enabled) {
    _reducedMotion = enabled;
    crux.logger.i('Reduced motion: $_reducedMotion');
  }

  /// Active/désactive le lecteur d'écran
  void setScreenReaderEnabled(bool enabled) {
    _screenReaderEnabled = enabled;
    crux.logger.i('Screen reader enabled: $_screenReaderEnabled');
  }

  /// Obtient les paramètres d'accessibilité du système
  void syncWithSystemSettings(MediaQueryData mediaQuery) {
    _highContrastMode = mediaQuery.highContrast;
    _reducedMotion = mediaQuery.disableAnimations;
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
    VoidCallback? onIncrease,
    VoidCallback? onDecrease,
    SemanticsSortKey? sortKey,
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
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      sortKey: sortKey,
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

  /// Construit un widget sémantiquement accessible
  Widget buildAccessibleWidget({
    required Widget child,
    required String label,
    String? hint,
    bool enabled = true,
    bool button = false,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      enabled: enabled,
      button: button,
      child: child,
    );
  }
}
