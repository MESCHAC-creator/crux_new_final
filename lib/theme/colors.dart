import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Obsidienne profonde (plus foncé) ────────────────────────────────────
  static const Color _obsidian = Color(0xFF030405); // noir absolu
  static const Color _obsidian2 = Color(0xFF080A0D);
  static const Color _charcoal = Color(0xFF0F1114);
  static const Color _slate800 = Color(0xFF15191F);
  static const Color _slate700 = Color(0xFF1B202A);
  static const Color _slate600 = Color(0xFF242A35);

  // ── Blanc/Argent (MOINS brillant) ──────────────────────────────────────
  static const Color _white = Color(0xFFE8EBF0); // blanc cassé, moins éblouissant
  static const Color _iceWhite = Color(0xFFD9DCE3);
  static const Color _silver = Color(0xFFC0C5CF);
  static const Color _silverDim = Color(0xFF9FA5B3);
  static const Color _coolGray = Color(0xFF7A8291);
  static const Color _mutedGray = Color(0xFF556070);

  // ── Accents fonctionnels (étouffés) ────────────────────────────────────
  static const Color _cyan400 = Color(0xFF00D4E8); // cyan moins vif
  static const Color _cyan500 = Color(0xFF009FB8);
  static const Color _green500 = Color(0xFF00D166);
  static const Color _red500 = Color(0xFFE83333);
  static const Color _amber500 = Color(0xFFDFB13D);
  static const Color _orange500 = Color(0xFFEA6200);

  // ── Sémantiques — Marque ───────────────────────────────────────────────
  static const Color primary = _iceWhite;
  static const Color primaryLight = _white;
  static const Color primaryDark = _silver;
  static const Color secondary = _silverDim;

  static const Color accentLive = _cyan400;
  static const Color accentLiveDark = _cyan500;

  // ── Surfaces ───────────────────────────────────────────────────────────
  static const Color background = _obsidian;
  static const Color backgroundElevated = _obsidian2;
  static const Color surface = _charcoal;
  static const Color surfaceVariant = _slate800;
  static const Color surfaceElevated = _slate700;
  static const Color cardBackground = _slate600;

  // ── Texte ──────────────────────────────────────────────────────────────
  static const Color textPrimary = _iceWhite;
  static const Color textSecondary = _coolGray;
  static const Color textTertiary = _mutedGray;
  static const Color textDisabled = Color(0xFF353A46);
  static const Color textOnPrimary = _obsidian;

  // ── Bordures ───────────────────────────────────────────────────────────
  static const Color border = Color(0xFF1F2329);
  static const Color borderSubtle = Color(0xFF17191F);
  static const Color borderFocused = _silver;
  static const Color divider = Color(0xFF14171D);

  // ── États ──────────────────────────────────────────────────────────────
  static const Color success = _green500;
  static const Color successSurface = Color(0xFF092115);
  static const Color error = _red500;
  static const Color errorSurface = Color(0xFF290909);
  static const Color warning = _amber500;
  static const Color warningSurface = Color(0xFF281D02);
  static const Color info = _silver;
  static const Color infoSurface = Color(0xFF171A21);
  static const Color whiteBg = Color(0xFFE8EBF0);

  // ── Réunion ────────────────────────────────────────────────────────────
  static const Color micActive = _green500;
  static const Color micMuted = _red500;
  static const Color cameraActive = _green500;
  static const Color cameraOff = _mutedGray;
  static const Color screenShareActive = _cyan400;
  static const Color recordingActive = _red500;
  static const Color handRaised = _amber500;
  static const Color liveDot = _cyan400;

  // ── Réseau ─────────────────────────────────────────────────────────────
  static const Color networkExcellent = _green500;
  static const Color networkGood = _amber500;
  static const Color networkPoor = _orange500;
  static const Color networkCritical = _red500;

  // ── PRO Badge ──────────────────────────────────────────────────────────
  static const Color proBadge = _silver;
  static const Color proBadgeSurface = Color(0xFF1A1F2A);

  // ── Gradients ──────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_white, _silver],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_obsidian2, _obsidian],
  );

  static const RadialGradient logoHalo = RadialGradient(
    colors: [Color(0x1EFFFFFF), Color(0x00FFFFFF)],
    radius: 0.75,
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_slate700, _slate800],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x0CFFFFFF), Color(0x02FFFFFF)],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE83333), Color(0xFF7A0A0A)],
  );

  static const LinearGradient liveGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_cyan400, _cyan500],
  );

  // ── Overlays ───────────────────────────────────────────────────────────
  static Color overlayLight = _white.withValues(alpha: 0.04);
  static Color overlayMedium = _white.withValues(alpha: 0.08);
  static Color overlayStrong = _white.withValues(alpha: 0.14);
  static Color scrim = _obsidian.withValues(alpha: 0.88);

  // ── Ombres ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: _obsidian.withValues(alpha: 0.7),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: _white.withValues(alpha: 0.06),
          blurRadius: 30,
          spreadRadius: -6,
        ),
      ];

  // ── Helpers ────────────────────────────────────────────────────────────
  static Color primaryWithOpacity(double opacity) =>
      _iceWhite.withValues(alpha: opacity);
  static Color whiteWithOpacity(double opacity) =>
      _white.withValues(alpha: opacity);
  static Color errorWithOpacity(double opacity) =>
      _red500.withValues(alpha: opacity);
  static Color liveWithOpacity(double opacity) =>
      _cyan400.withValues(alpha: opacity);
}
