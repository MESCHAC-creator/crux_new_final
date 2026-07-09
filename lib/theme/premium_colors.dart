import 'package:flutter/material.dart';

/// Palette Premium CRUX avec sensation Feu & Chaleur
/// Blanc, Bleu & Rouge - Design Moderne & Professionnel
class PremiumColors {
  // Primary Colors - Fire sensation
  static const Color flamePrimary = Color(0xFFFF4F38); // Feu vif
  static const Color flameLight = Color(0xFFFF6B52); // Feu clair
  static const Color flameDark = Color(0xFFE63D28); // Feu sombre

  // Secondary Colors - Ice/Calm (contraste)
  static const Color icePrimary = Color(0xFF1E88E5); // Bleu premium
  static const Color iceLight = Color(0xFF42A5F5); // Bleu clair
  static const Color iceDark = Color(0xFF1565C0); // Bleu sombre

  // Accent Colors
  static const Color accentOrange = Color(0xFFFF9800); // Chaleur
  static const Color accentGolden = Color(0xFFFFB74D); // Dorure

  // Neutral & Background
  static const Color cloudWhite = Color(0xFFFAFAFA); // Blanc premium
  static const Color snowWhite = Color(0xFFFFFFFF); // Blanc pur
  static const Color darkBackground = Color(0xFF0F1419); // Noir premium
  static const Color surfaceGray = Color(0xFFF5F5F5); // Surface grise
  static const Color borderGray = Color(0xFFE0E0E0); // Bordure grise

  // Semantic Colors
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color warningYellow = Color(0xFFFFC107);
  static const Color errorRed = Color(0xFFE74C3C);
  static const Color infoBlue = Color(0xFF2196F3);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A); // Noir texte
  static const Color textSecondary = Color(0xFF666666); // Gris texte
  static const Color textTertiary = Color(0xFF999999); // Gris clair
  static const Color textInverse = Color(0xFFFFFFFF); // Blanc sur fond sombre

  // Gradient - Fire Sensation
  static const List<Color> fireGradient = [
    flamePrimary, // Feu vif
    Color(0xFFFF6B4A), // Feu moyen
    accentOrange, // Chaleur
  ];

  // Gradient - Cool & Professional
  static const List<Color> coolGradient = [
    icePrimary, // Bleu
    iceLight, // Bleu clair
  ];

  // Gradient - Sophisticated (Mix)
  static const List<Color> luxeGradient = [
    flamePrimary,
    accentOrange,
    icePrimary,
  ];

  // Background Gradients
  static const LinearGradient fireBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: fireGradient,
  );

  static const LinearGradient coolBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: coolGradient,
  );

  static const LinearGradient luxeBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: luxeGradient,
  );

  // Opacity variants
  static Color flamePrimaryWithOpacity(double opacity) =>
      flamePrimary.withOpacity(opacity);
  static Color icePrimaryWithOpacity(double opacity) =>
      icePrimary.withOpacity(opacity);
  static Color textPrimaryWithOpacity(double opacity) =>
      textPrimary.withOpacity(opacity);

  // Shadow Colors
  static const Color shadowDark = Color.fromRGBO(0, 0, 0, 0.25);
  static const Color shadowMedium = Color.fromRGBO(0, 0, 0, 0.15);
  static const Color shadowLight = Color.fromRGBO(0, 0, 0, 0.08);

  // Glow effect colors
  static const Color fireGlow = Color.fromRGBO(255, 79, 56, 0.2);
  static const Color iceGlow = Color.fromRGBO(30, 136, 229, 0.2);
}
