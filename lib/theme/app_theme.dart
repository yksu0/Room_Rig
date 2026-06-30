// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF0A0B0F);
  static const surface = Color(0xFF12141A);
  static const surfaceAlt = Color(0xFF1A1D26);
  static const card = Color(0xFF1E2230);
  static const border = Color(0xFF2A2F42);

  static const cyan = Color(0xFF00E5FF);
  static const cyanDim = Color(0xFF0097A7);
  static const purple = Color(0xFF7C4DFF);
  static const purpleDim = Color(0xFF4527A0);
  static const amber = Color(0xFFFFAB00);
  static const green = Color(0xFF00E676);
  static const red = Color(0xFFFF3D00);
  static const orange = Color(0xFFFF6D00);

  static const textPrimary = Color(0xFFF0F2FF);
  static const textSecondary = Color(0xFF8B93B8);
  static const textMuted = Color(0xFF4A5070);

  static const airflowColor = Color(0xFF00E5FF);
  static const lightingColor = Color(0xFFFFE57F);
  static const ergonomicsColor = Color(0xFF69FF47);

  static LinearGradient get accentGradient => const LinearGradient(
    colors: [cyan, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get cardGradient => const LinearGradient(
    colors: [Color(0xFF1E2230), Color(0xFF161926)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.cyan,
        secondary: AppColors.purple,
        error: AppColors.red,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}
