import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black87,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(
          fontSize: 57, fontWeight: FontWeight.w700, color: Colors.black87,
        ),
        headlineSmall: GoogleFonts.spaceGrotesk(
          fontSize: 24, fontWeight: FontWeight.w600, color: Colors.black87,
        ),
        bodyLarge: GoogleFonts.spaceGrotesk(
          fontSize: 16, fontWeight: FontWeight.w400, color: Colors.black87,
        ),
        bodyMedium: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w400, color: Colors.black54,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,

      // ── ColorScheme complet M3 ──────────────────────────────────────
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.textOnPrimary,
        primaryContainer: Color(0xFF003340),
        onPrimaryContainer: AppColors.primaryLight,
        secondary: AppColors.secondary,
        onSecondary: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.surfaceVariant,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.divider,
        error: AppColors.error,
        onError: AppColors.textPrimary,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: AppColors.textPrimary,
        onInverseSurface: AppColors.background,
      ),

      // ── Typographie Space Grotesk ───────────────────────────────────
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(
          fontSize: 57, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.spaceGrotesk(
          fontSize: 45, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary, letterSpacing: -0.5,
        ),
        displaySmall: GoogleFonts.spaceGrotesk(
          fontSize: 36, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineLarge: GoogleFonts.spaceGrotesk(
          fontSize: 32, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          fontSize: 28, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineSmall: GoogleFonts.spaceGrotesk(
          fontSize: 24, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 16, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary, letterSpacing: 0.15,
        ),
        titleSmall: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w500,
          color: AppColors.textPrimary, letterSpacing: 0.1,
        ),
        bodyLarge: GoogleFonts.spaceGrotesk(
          fontSize: 16, fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        bodySmall: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w400,
          color: AppColors.textTertiary,
        ),
        labelLarge: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary, letterSpacing: 0.1,
        ),
        labelMedium: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary, letterSpacing: 0.5,
        ),
        labelSmall: GoogleFonts.spaceGrotesk(
          fontSize: 11, fontWeight: FontWeight.w500,
          color: AppColors.textTertiary, letterSpacing: 0.5,
        ),
      ),

      // ── AppBar ──────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 24),
        actionsIconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
      ),

      // ── Boutons primaires ────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3,
          ),
        ),
      ),

      // ── Boutons outline ──────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3,
          ),
        ),
      ),

      // ── Boutons texte ────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 14, fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── FilledButton ─────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // ── Inputs ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14, color: AppColors.textTertiary,
        ),
        labelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14, color: AppColors.textSecondary,
        ),
        floatingLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 12, color: AppColors.primary,
        ),
        errorStyle: GoogleFonts.spaceGrotesk(
          fontSize: 12, color: AppColors.error,
        ),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
      ),

      // ── Cards ────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── ListTile ─────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
        ),
        subtitleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
        ),
        leadingAndTrailingTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 12, color: AppColors.textTertiary,
        ),
        iconColor: AppColors.textSecondary,
      ),

      // ── Divider ──────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── BottomNavigationBar ──────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 11, fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 11, fontWeight: FontWeight.w400,
        ),
      ),

      // ── Chips ────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        selectedColor: AppColors.primaryWithOpacity(0.2),
        side: const BorderSide(color: AppColors.border, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Dialog ───────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceVariant,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14, color: AppColors.textSecondary,
        ),
      ),

      // ── SnackBar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14, color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        actionTextColor: AppColors.primary,
      ),

      // ── Switch / Checkbox / Radio ─────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.textOnPrimary;
          return AppColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.border;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.textOnPrimary),
        side: const BorderSide(color: AppColors.border, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // ── FloatingActionButton ──────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // ── IconButton ────────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // ── Progress indicators ───────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),

      // ── BottomSheet ───────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        dragHandleColor: AppColors.border,
        dragHandleSize: Size(40, 4),
      ),

      // ── Tab bar ───────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
        ),
        labelStyle: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w400),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
    );
  }
}
