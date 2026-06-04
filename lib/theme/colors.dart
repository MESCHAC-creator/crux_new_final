import 'package:flutter/material.dart';

class AppColors {
  // PRIMARY — Blood Red
  static const Color primary = Color(0xFFB71C1C);        // sang profond
  static const Color primaryDark = Color(0xFF7F0000);    // rouge abyssal
  static const Color primaryLight = Color(0xFFE53935);   // rouge vif

  // SECONDARY — Cross Purple
  static const Color secondary = Color(0xFF6A1B9A);      // violet croix
  static const Color secondaryDark = Color(0xFF38006B);  // violet obscur
  static const Color secondaryLight = Color(0xFF9C27B0); // violet électrique

  // ACCENT — Art White / Lavande
  static const Color accent = Color(0xFF7B1FA2);         // violet artistique
  static const Color accentLight = Color(0xFFE1BEE7);    // lavande douce

  // Backgrounds
  static const Color whiteBg = Color(0xFFFFFFFF);
  static const Color lightBg = Color(0xFFFAF8FF);        // légèrement teintée violet
  static const Color mediumBg = Color(0xFFF0EBF8);       // parchemin violet pâle

  // Gradient backgrounds
  static const Color bgGradient1 = Color(0xFFF8F5FF);
  static const Color bgGradient2 = Color(0xFFEDE7F6);

  // TEXT COLORS
  static const Color textPrimary = Color(0xFF1A0A2E);    // presque noir violet
  static const Color textSecondary = Color(0xFF4A3560);
  static const Color textTertiary = Color(0xFF9E8FAF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // STATUS
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFB71C1C);
  static const Color warning = Color(0xFFE65100);
  static const Color info = Color(0xFF1565C0);
  static const Color pending = Color(0xFF78909C);

  // BORDERS
  static const Color border = Color(0xFFD1C4E9);
  static const Color divider = Color(0xFFEDE7F6);
  static const Color borderFocus = Color(0xFF6A1B9A);

  // OVERLAY
  static const Color overlay = Color(0x00000000);
  static const Color overlayLight = Color(0x20000000);
  static const Color overlayDark = Color(0x80000000);

  // SPECIAL STATES
  static const Color onlineGreen = Color(0xFF2E7D32);
  static const Color offlineGray = Color(0xFF78909C);
  static const Color busyRed = Color(0xFFB71C1C);
  static const Color awayYellow = Color(0xFFE65100);

  // PRIMARY GRADIENT — Blood red → Cross purple (dramatic)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)],
  );

  // ACCENT GRADIENT — Cross purple → Deeper
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF9C27B0), Color(0xFF7F0000)],
  );

  // PREMIUM GRADIENT — Crimson → Purple → White-art
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A), Color(0xFFF8F5FF)],
  );
}

// Palette couleurs pour thèmes différents
class AppColorsPalette {
  // Theme Clair (Jour)
  static const Map<String, Color> lightTheme = {
    'primary': Color(0xFFB71C1C),
    'secondary': Color(0xFF6A1B9A),
    'background': Color(0xFFFFFFFF),
    'surface': Color(0xFFFAF8FF),
    'text': Color(0xFF1A0A2E),
  };

  // Theme Sombre (Nuit)
  static const Map<String, Color> darkTheme = {
    'primary': Color(0xFFE53935),
    'secondary': Color(0xFF9C27B0),
    'background': Color(0xFF0F0F0F),
    'surface': Color(0xFF1A1A1A),
    'text': Color(0xFFFFFFFF),
  };
}
