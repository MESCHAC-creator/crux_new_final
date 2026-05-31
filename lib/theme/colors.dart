import 'package:flutter/material.dart';

class AppColors {
  // 🔴 PRIMARY COLORS - ROUGE & VIOLET & BLANC
  static const Color primary = Color(0xFFE74C3C); // Rouge vibrant
  static const Color primaryDark = Color(0xFFC0392B); // Rouge foncé
  static const Color primaryLight = Color(0xFFF8706E); // Rouge clair

  static const Color secondary = Color(0xFF8E44AD); // Violet principal
  static const Color secondaryDark = Color(0xFF6C3483); // Violet foncé
  static const Color secondaryLight = Color(0xFFBB8FCE); // Violet clair

  static const Color accent = Color(0xFF9B59B6); // Violet accent
  static const Color accentLight = Color(0xFFD7BDE2); // Violet très clair

  // ⚪ BACKGROUND - BLANC & GRIS (Premium)
  static const Color whiteBg = Color(0xFFFFFFFF); // Blanc pur
  static const Color lightBg = Color(0xFFF8F9FA); // Blanc cassé
  static const Color mediumBg = Color(0xFFEEF0F4); // Gris très clair

  // Gradient backgrounds
  static const Color bgGradient1 = Color(0xFFF5F7FA); // Fond dégradé 1
  static const Color bgGradient2 = Color(0xFFE8EAEF); // Fond dégradé 2

  // TEXT COLORS
  static const Color textPrimary = Color(0xFF1A1A1A); // Noir texte
  static const Color textSecondary = Color(0xFF555555); // Gris texte
  static const Color textTertiary = Color(0xFF999999); // Gris clair texte
  static const Color textOnPrimary = Color(0xFFFFFFFF); // Blanc sur rouge

  // STATUS & FEEDBACK
  static const Color success = Color(0xFF27AE60); // Vert succès
  static const Color error = Color(0xFFE74C3C); // Rouge erreur (même que primary)
  static const Color warning = Color(0xFFF39C12); // Orange warning
  static const Color info = Color(0xFF3498DB); // Bleu info
  static const Color pending = Color(0xFF95A5A6); // Gris en attente

  // BORDERS & DIVIDERS
  static const Color border = Color(0xFFDCDCDC); // Border gris clair
  static const Color divider = Color(0xFFE8EAEF); // Divider léger
  static const Color borderFocus = Color(0xFF8E44AD); // Border violet focus

  // OVERLAY & SHADOWS
  static const Color overlay = Color(0x00000000); // Transparent
  static const Color overlayLight = Color(0x20000000); // Overlay léger
  static const Color overlayDark = Color(0x80000000); // Overlay sombre

  // SPECIAL STATES
  static const Color onlineGreen = Color(0xFF27AE60); // En ligne
  static const Color offlineGray = Color(0xFF95A5A6); // Hors ligne
  static const Color busyRed = Color(0xFFE74C3C); // Occupé
  static const Color awayYellow = Color(0xFFF39C12); // Absent

  // GRADIENT COMBINATIONS (Meilleur que Zoom & Google Meet!)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE74C3C), // Rouge
      Color(0xFF8E44AD), // Violet
    ],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0xFF8E44AD), // Violet
      Color(0xFFC0392B), // Rouge foncé
    ],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF8706E), // Rouge clair
      Color(0xFFBB8FCE), // Violet clair
      Color(0xFFFFFFFF), // Blanc
    ],
  );
}

// Pallette couleurs pour thèmes différents
class AppColorsPalette {
  // Theme Clair (Jour)
  static const Map<String, Color> lightTheme = {
    'primary': Color(0xFFE74C3C),
    'secondary': Color(0xFF8E44AD),
    'background': Color(0xFFFFFFFF),
    'surface': Color(0xFFF8F9FA),
    'text': Color(0xFF1A1A1A),
  };

  // Theme Sombre (Nuit)
  static const Map<String, Color> darkTheme = {
    'primary': Color(0xFFF8706E),
    'secondary': Color(0xFFBB8FCE),
    'background': Color(0xFF0F0F0F),
    'surface': Color(0xFF1A1A1A),
    'text': Color(0xFFFFFFFF),
  };
}