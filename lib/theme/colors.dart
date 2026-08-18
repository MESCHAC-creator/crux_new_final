import 'package:flutter/material.dart';

/// ==========================================================================
///  CRUX — Palette « Obsidian Mono »
/// ==========================================================================
/// Le logo CRUX est monochrome : croix blanche laquée sur obsidienne, reflets
/// argent. L'ancienne palette poussait un cyan électrique dominant qui ne
/// figure nulle part dans l'identité → l'app et le logo semblaient venir de
/// deux marques différentes.
///
/// Nouvelle règle :
///   * accent principal = blanc / argent (comme le logo) ;
///   * profondeur obtenue par les niveaux d'obsidienne + halos, pas par la
///     couleur ;
///   * le cyan devient un accent *secondaire* réservé aux états « en direct »
///     (micro actif, partage d'écran), là où une couleur porte une information.
///
/// Tous les anciens noms de tokens sont conservés (`primary`, `primaryGradient`,
/// `borderFocused`…) : aucun écran existant ne casse, ils héritent simplement
/// du nouveau rendu monochrome.
class AppColors {
  AppColors._();

  // ── Primitives — Obsidienne ────────────────────────────────────────────
  static const Color _obsidian = Color(0xFF05070A); // fond le plus profond
  static const Color _obsidian2 = Color(0xFF0A0D12);
  static const Color _charcoal = Color(0xFF11141A);
  static const Color _slate800 = Color(0xFF171A21);
  static const Color _slate700 = Color(0xFF1E222B);
  static const Color _slate600 = Color(0xFF272C36);

  // ── Primitives — Argent / blanc (accent de marque) ─────────────────────
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _iceWhite = Color(0xFFF7F8FA);
  static const Color _silver = Color(0xFFD8DCE3);
  static const Color _silverDim = Color(0xFFAEB4BF);
  static const Color _coolGray = Color(0xFF8A909C);
  static const Color _mutedGray = Color(0xFF5E646F);

  // ── Primitives — Accents fonctionnels (usage strictement informatif) ───
  static const Color _cyan400 = Color(0xFF00E5FF);
  static const Color _cyan500 = Color(0xFF00B8D4);
  static const Color _green500 = Color(0xFF00E676);
  static const Color _red500 = Color(0xFFFF3D3D);
  static const Color _amber500 = Color(0xFFFFC94D);
  static const Color _orange500 = Color(0xFFFF6D00);

  // ── Sémantiques — Marque (désormais monochrome) ────────────────────────
  static const Color primary = _iceWhite;
  static const Color primaryLight = _white;
  static const Color primaryDark = _silver;
  static const Color secondary = _silverDim;

  /// Accent « en direct » : à n'utiliser que pour signaler une activité
  /// temps réel (jamais pour du décor).
  static const Color accentLive = _cyan400;
  static const Color accentLiveDark = _cyan500;

  // ── Sémantiques — Surfaces ─────────────────────────────────────────────
  static const Color background = _obsidian;
  static const Color backgroundElevated = _obsidian2;
  static const Color surface = _charcoal;
  static const Color surfaceVariant = _slate800;
  static const Color surfaceElevated = _slate700;
  static const Color cardBackground = _slate600;

  // ── Sémantiques — Texte ────────────────────────────────────────────────
  static const Color textPrimary = _iceWhite;
  static const Color textSecondary = _coolGray;
  static const Color textTertiary = _mutedGray;
  static const Color textDisabled = Color(0xFF3A3F49);
  static const Color textOnPrimary = _obsidian; // texte sur bouton blanc

  // ── Sémantiques — Bordures ─────────────────────────────────────────────
  static const Color border = Color(0xFF23272F);
  static const Color borderSubtle = Color(0xFF1A1D24);
  static const Color borderFocused = _silver;
  static const Color divider = Color(0xFF181B21);

  // ── Sémantiques — États ────────────────────────────────────────────────
  static const Color success = _green500;
  static const Color successSurface = Color(0xFF0A2417);
  static const Color error = _red500;
  static const Color errorSurface = Color(0xFF2A0C0C);
  static const Color warning = _amber500;
  static const Color warningSurface = Color(0xFF291F05);
  static const Color info = _silver;
  static const Color infoSurface = Color(0xFF1A1D24);
  static const Color whiteBg = Color(0xFFFFFFFF);

  // ── Sémantiques — Réunion ──────────────────────────────────────────────
  static const Color micActive = _green500;
  static const Color micMuted = _red500;
  static const Color cameraActive = _green500;
  static const Color cameraOff = _mutedGray;
  static const Color screenShareActive = _cyan400;
  static const Color recordingActive = _red500;
  static const Color handRaised = _amber500;
  static const Color liveDot = _cyan400;

  // ── Sémantiques — Réseau ───────────────────────────────────────────────
  static const Color networkExcellent = _green500;
  static const Color networkGood = _amber500;
  static const Color networkPoor = _orange500;
  static const Color networkCritical = _red500;

  // ── PRO Badge (argent brossé plutôt que doré criard) ───────────────────
  static const Color proBadge = _silver;
  static const Color proBadgeSurface = Color(0xFF1C2029);

  // ── Gradients ──────────────────────────────────────────────────────────

  /// Bouton principal : argent laqué (reflet du logo).
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_white, _silver],
  );

  /// Fond d'écran d'accueil : profondeur obsidienne verticale.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_obsidian2, _obsidian],
  );

  /// Halo derrière le logo / la carte principale.
  static const RadialGradient logoHalo = RadialGradient(
    colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
    radius: 0.75,
  );

  /// Cartes : léger dégradé pour éviter les aplats plats.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_slate700, _slate800],
  );

  /// Verre dépoli (surfaces flottantes, bottom nav).
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)],
  );

  static const LinearGradient dangerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF3D3D), Color(0xFF8E1111)],
  );

  /// Réservé au badge « En direct ».
  static const LinearGradient liveGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_cyan400, _cyan500],
  );

  // ── Overlays ───────────────────────────────────────────────────────────
  static Color overlayLight = _white.withValues(alpha: 0.06);
  static Color overlayMedium = _white.withValues(alpha: 0.12);
  static Color overlayStrong = _white.withValues(alpha: 0.20);
  static Color scrim = _obsidian.withValues(alpha: 0.85);

  // ── Ombres ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: _obsidian.withValues(alpha: 0.6),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: _white.withValues(alpha: 0.10),
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
