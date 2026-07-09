import 'package:flutter/material.dart';

class AppColors {
  // CRUX Premium Obsidian & Electric Neon Palette
  static const Color primary = Color(0xFF00E5FF); // Electric Cyan
  static const Color secondary = Color(0xFF7C5CFF); // Electric Violet
  static const Color background = Color(0xFF0A0E1A); // Deep Navy Dark
  static const Color surface = Color(0xFF121624); // Deep Slate Gray
  static const Color textPrimary = Color(0xFFFAFAFA); // Ice White
  static const Color textSecondary = Color(0xFF8A8FA3); // Cool Gray
  static const Color accent = Color(0xFF00E5FF); // Electric Cyan
  static const Color success = Color(0xFF00E676); // Neon Green
  static const Color error = Color(0xFFFF3D00); // Bright Red
  static const Color info = Color(0xFF00E5FF); // Electric Cyan

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5FF), Color(0xFF7C5CFF)],
  );

  static const Color whiteBg = Color(0xFFFFFFFF);
}

