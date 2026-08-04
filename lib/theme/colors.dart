// lib/theme/colors.dart
import 'package:flutter/material.dart';

/// CRUX Design Tokens — Palette Obsidian & Electric Cyan
/// Un seul fichier de référence : jamais de couleur hardcodée ailleurs.
class AppColors {
  AppColors._();

  // ── Primitives ─────────────────────────────────────────────────────────
  static const Color _cyan400 = Color(0xFF00E5FF);
  static const Color _cyan300 = Color(0xFF4DFBFF);
  static const Color _cyan500 = Color(0xFF00B8D4);
  static const Color _indigo400 = Color(0xFFF4E6BFF);
  static const Color _indigoAccent = Color(0xFF536DFE);

  static const Color _obsidian = Color(0xFF05070D);
  static const Color _charcoal = Color(0xFF10131D);
  static const Color _slate800 = Color(0xFF151925);
  static const Color _slate700 = Color(0xFF1C2135);
  static const Color _slate600 = Color(0xFF252B3A);

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _iceWhite = Color(0xFFFFFAFA);
  static const Color _coolGray = Color(0xFF9AA0B5);
  static const Color _mutedGray = Color(0xFF697086);

  static const Color _green500 = Color(0xFF00E676);
  static const Color _red500 = Color(0xFFFF3D00);
  static const Color _amber500 = Color(0xFFFFD740);
  static const Color _orange500 = Color(0xFFFF6D00);

  // ── Sémantiques — Marque ───────────────────────────────────────────────
  static const Color primary = _cyan400;
  static const Color primaryLight = _cyan300;
  static const Color primaryDark = _cyan500;
  static const Color secondary = _indigoAccent;

  // ── Sémantiques — Surfaces ─────────────────────────────────────────────
  static const Color background = _obsidian;
  static const Color surface = _charcoal;
  static const Color surfaceVariant = _slate800;
  static const Color surfaceElevated = _slate700;
  static const Color cardBackground = _slate600;

  // ── Sémantiques — Texte ────────────────────────────────────────────────
  static const Color textPrimary = _iceWhite;
  static const Color textSecondary = _coolGray;
  static const Color textTertiary = _mutedGray;
  static const Color textDisabled = Color(0xFF3D4360);
  static const Color textOnPrimary = _obsidian;

  // ── Sémantiques — Bordures ─────────────────────────────────────────────
  static const Color border = Color(0xFF252B3A);
  static const Color borderFocused = _cyan400;
  static const Color divider = Color(0xFF1A1F2E);

  // ── Sémantiques — États ────────────────────────────────────────────────
  static const Color success = _green500;
  static const Color successSurface = Color(0xFF0A2B1A);
  static const Color error = _red500;
  static const Color errorSurface = Color(0xFF2B0A0A);
  static const Color warning = _amber500;
  static const Color warningSurface = Color(0xFF2B2000);
  static const Color info = _cyan400;
  static const Color infoSurface = Color(0xFF002B33);

  // ── Sémantiques — Réunion ──────────────────────────────────────────────
  static const Color micActive = _green500;
  static const Color micMuted = _red500;
  static const Color cameraActive = _green500;
  static const Color cameraOff = _mutedGray;
  static const Color screenShareActive = _cyan400;
  static const Color recordingActive = _red500;
  static const Color handRaised = _amber500;

  // ── Sémantiques — Réseau ──────────────────────────────────────────────
  static const Color networkExcellent = _green500;
  static const Color networkGood = _amber500;
  static const Color networkPoor = _orange500;
  static const Color networkCritical = _red500;

  // ── PRO Badge ─────────────────────────────────────────────────────────
  static const Color proBadge = _amber500;
  static const Color proBadgeSurface = Color(0xFF2B1F00);

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_cyan400, _cyan500],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_obsidian, _charcoal],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_slate700, _slate800],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF3D00), Color(0xFFB71C1C)],
  );

  // ── Overlays ──────────────────────────────────────────────────────────
  static Color overlayLight = _white.withOpacity(0.06);
  static Color overlayMedium = _white.withOpacity(0.12);
  static Color scrim = _obsidian.withOpacity(0.85);

  // ── Helpers ───────────────────────────────────────────────────────────
  static Color primaryWithOpacity(double opacity) => _cyan400.withOpacity(opacity);
  static Color errorWithOpacity(double opacity) => _red500.withOpacity(opacity);
}
