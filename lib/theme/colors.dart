import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Noirs profonds (base) ──────────────────────────────────────────────
  static const Color _black = Color(0xFF0a0a0a);
  static const Color _charcoal = Color(0xFF0f0f0f);
  static const Color _darkGray = Color(0xFF1a1a1a);
  static const Color _darkGray2 = Color(0xFF242424);
  static const Color _darkGray3 = Color(0xFF2e2e2e);
  static const Color _darkGray4 = Color(0xFF383838);

  // ── Gris neutres (pas blanc brillant) ──────────────────────────────────
  static const Color _white = Color(0xFFd0d0d0);
  static const Color _lightGray = Color(0xFFa8a8a8);
  static const Color _mediumGray = Color(0xFF808080);
  static const Color _gray = Color(0xFF606060);
  static const Color _dimGray = Color(0xFF404040);

  // ── Accents fonctionnels (très étouffés) ───────────────────────────────
  static const Color _cyan = Color(0xFF0099bb);
  static const Color _green = Color(0xFF00aa55);
  static const Color _red = Color(0xFFbb3333);
  static const Color _orange = Color(0xFFdd7722);
  static const Color _amber = Color(0xFFccaa33);

  // ── Sémantiques ────────────────────────────────────────────────────────
  static const Color primary = _white;
  static const Color primaryLight = Color(0xFFe0e0e0);
  static const Color primaryDark = _lightGray;
  static const Color secondary = _mediumGray;
  static const Color tertiary = _gray;

  // ── Surfaces ───────────────────────────────────────────────────────────
  static const Color background = _black;
  static const Color surface = _charcoal;
  static const Color surfaceVariant = _darkGray;
  static const Color surfaceElevated = _darkGray2;
  static const Color cardBackground = _darkGray3;
  static const Color cardBackgroundAlt = _darkGray4;

  // ── Texte ──────────────────────────────────────────────────────────────
  static const Color textPrimary = _white;
  static const Color textSecondary = _mediumGray;
  static const Color textTertiary = _gray;
  static const Color textDisabled = Color(0xFF2a2a2a);
  static const Color textOnPrimary = _black;

  // ── Bordures ───────────────────────────────────────────────────────────
  static const Color border = Color(0xFF1f1f1f);
  static const Color borderSubtle = Color(0xFF141414);
  static const Color borderFocused = _lightGray;
  static const Color divider = Color(0xFF0f0f0f);

  // ── États ──────────────────────────────────────────────────────────────
  static const Color success = _green;
  static const Color successSurface = Color(0xFF0a1a0f);
  static const Color error = _red;
  static const Color errorSurface = Color(0xFF1a0a0a);
  static const Color warning = _orange;
  static const Color warningSurface = Color(0xFF1a1410);
  static const Color info = _lightGray;
  static const Color infoSurface = Color(0xFF0f1214);

  // ── Réunion ────────────────────────────────────────────────────────────
  static const Color micActive = _green;
  static const Color micMuted = _red;
  static const Color cameraActive = _green;
  static const Color cameraOff = _mediumGray;
  static const Color screenShareActive = _cyan;
  static const Color recordingActive = _red;
  static const Color handRaised = _amber;
  static const Color liveDot = _cyan;

  // ── Réseau ─────────────────────────────────────────────────────────────
  static const Color networkExcellent = _green;
  static const Color networkGood = _amber;
  static const Color networkPoor = _orange;
  static const Color networkCritical = _red;

  // ── PRO Badge ──────────────────────────────────────────────────────────
  static const Color proBadge = _lightGray;
  static const Color proBadgeSurface = Color(0xFF0f1419);

  // ── Gradients ──────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_white, _lightGray],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_charcoal, _black],
  );

  static const RadialGradient logoHalo = RadialGradient(
    colors: [Color(0x0aFFFFFF), Color(0x00FFFFFF)],
    radius: 0.75,
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_darkGray2, _darkGray],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x05FFFFFF), Color(0x01FFFFFF)],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFbb3333), Color(0xFF440000)],
  );

  static const LinearGradient liveGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_cyan, Color(0xFF006688)],
  );

  // ── Overlays ───────────────────────────────────────────────────────────
  static Color overlayLight = _white.withValues(alpha: 0.03);
  static Color overlayMedium = _white.withValues(alpha: 0.06);
  static Color overlayStrong = _white.withValues(alpha: 0.10);
  static Color scrim = _black.withValues(alpha: 0.85);

  // ── Ombres ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: _black.withValues(alpha: 0.6),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: _white.withValues(alpha: 0.04),
          blurRadius: 24,
          spreadRadius: -4,
        ),
      ];

  // ── Helpers ────────────────────────────────────────────────────────────
  static Color primaryWithOpacity(double opacity) =>
      _white.withValues(alpha: opacity);
  static Color whiteWithOpacity(double opacity) =>
      _white.withValues(alpha: opacity);
  static Color errorWithOpacity(double opacity) =>
      _red.withValues(alpha: opacity);
  static Color liveWithOpacity(double opacity) =>
      _cyan.withValues(alpha: opacity);
}
