import 'package:flutter/material.dart';
import 'colors.dart';

class ConferenceTheme {
  ConferenceTheme._();

  // Extended colors for conference UI
  static const Color speakerBorder = AppColors.primaryLight;
  static const Color activeSpeakerGlow = Color(0x33F7F8FA);
  static const Color feedBg = AppColors.surfaceVariant;
  static const Color speakerOverlay = Color(0x8005070A);
  
  // Audio visualization colors
  static const Color audioWave = AppColors.cyan;
  static const Color audioWaveBackground = AppColors.borderSubtle;
  
  // Reaction colors
  static const Color reactionBackground = Color(0x20F7F8FA);
  static const Color reactionHighlight = AppColors.primary;

  // Duration constants for animations
  static const Duration speakerTransition = Duration(milliseconds: 300);
  static const Duration emojiParticle = Duration(seconds: 3);
  static const Duration controlFade = Duration(seconds: 2);
  static const Duration feedScroll = Duration(milliseconds: 500);
  static const Duration layoutChange = Duration(milliseconds: 400);
  static const Duration particleFade = Duration(milliseconds: 800);
  
  // Animation curves
  static const Curve speakerCurve = Curves.easeOut;
  static const Curve emojiCurve = Curves.easeInCubic;
  static const Curve controlCurve = Curves.easeInOut;
  static const Curve feedCurve = Curves.easeOutCubic;
  static const Curve layoutCurve = Curves.easeInOutCubic;

  // Sizes
  static const double speakerBorderWidth = 2.0;
  static const double activeSpeakerBorderWidth = 3.0;
  static const double feedItemHeight = 56.0;
  static const double feedItemWidth = 80.0;
  static const double controlButtonSize = 48.0;
  static const double networkStatsWidth = 100.0;
  static const double networkStatsExpandedWidth = 200.0;
  
  // Border radius
  static const double speakerRadius = AppColors.radiusCard;
  static const double feedItemRadius = 8.0;
  static const double controlRadius = 30.0;
  static const double statsRadius = 12.0;

  // Shadows
  static List<BoxShadow> get speakerShadow => [
        BoxShadow(
          color: activeSpeakerGlow,
          blurRadius: 20,
          spreadRadius: 5,
        ),
      ];

  static List<BoxShadow> get feedShadow => [
        BoxShadow(
          color: AppColors.surface.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get controlShadow => [
        BoxShadow(
          color: AppColors.surface.withValues(alpha: 0.5),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ];

  // Gradients
  static const LinearGradient speakerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x0005070A),
      Color(0x8005070A),
      Color(0xD005070A),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient activeSpeakerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x20F7F8FA),
      Color(0x40F7F8FA),
      Color(0x60F7F8FA),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Text styles
  static const TextStyle speakerNameStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle feedNameStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle statsLabelStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 11,
  );

  static const TextStyle statsValueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  // Get theme data for conference screens
  static ThemeData get conferenceTheme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 24,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textSecondary),
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        background: AppColors.background,
        error: AppColors.error,
      ),
    );
  }

  // Speaker appearance animation
  static Animation<double> speakerAppearanceAnimation(
    AnimationController controller,
  ) {
    return Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: speakerCurve,
      ),
    );
  }

  // Control fade animation
  static Animation<double> controlFadeAnimation(
    AnimationController controller,
  ) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: controlCurve,
      ),
    );
  }

  // Feed scroll animation
  static Animation<Offset> feedScrollAnimation(
    AnimationController controller,
  ) {
    return Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: feedCurve,
      ),
    );
  }
}