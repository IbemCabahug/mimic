// lib/core/theme/horror_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HorrorColors {
  static const Color voidBlack = Color(0xFF080A0F);
  static const Color deepSurface = Color(0xFF0D1117);
  static const Color cardSurface = Color(0xFF1A1F2E);
  static const Color bloodRed = Color(0xFF8B0000);
  static const Color crimson = Color(0xFFC41E3A);
  static const Color fogWhite = Color(0xFFE8E0D0);
  static const Color ashGray = Color(0xFF6B7280);
  static const Color darkRedTint = Color(0xFF2D1B1B);
}

class HorrorTheme {
  static ThemeData get themeData {
    final displayFont = GoogleFonts.creepster();
    final bodyFont = GoogleFonts.inter();

    final textTheme = TextTheme(
      displayLarge: displayFont.copyWith(color: HorrorColors.fogWhite),
      displayMedium: displayFont.copyWith(color: HorrorColors.fogWhite),
      displaySmall: displayFont.copyWith(color: HorrorColors.fogWhite),
      headlineLarge: displayFont.copyWith(color: HorrorColors.fogWhite),
      headlineMedium: displayFont.copyWith(color: HorrorColors.fogWhite),
      headlineSmall: displayFont.copyWith(color: HorrorColors.fogWhite),
      titleLarge: displayFont.copyWith(color: HorrorColors.fogWhite),
      titleMedium: displayFont.copyWith(color: HorrorColors.fogWhite),
      titleSmall: displayFont.copyWith(color: HorrorColors.fogWhite),
      bodyLarge: bodyFont.copyWith(color: HorrorColors.fogWhite),
      bodyMedium: bodyFont.copyWith(color: HorrorColors.fogWhite),
      bodySmall: bodyFont.copyWith(color: HorrorColors.ashGray),
      labelLarge: bodyFont.copyWith(color: HorrorColors.fogWhite),
      labelMedium: bodyFont.copyWith(color: HorrorColors.fogWhite),
      labelSmall: bodyFont.copyWith(color: HorrorColors.ashGray),
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HorrorColors.voidBlack,
      cardColor: HorrorColors.cardSurface,
      primaryColor: HorrorColors.crimson,
      colorScheme: const ColorScheme.dark(
        primary: HorrorColors.crimson,
        secondary: HorrorColors.bloodRed,
        surface: HorrorColors.deepSurface,
        error: HorrorColors.crimson,
      ),
      textTheme: textTheme,
      fontFamily: bodyFont.fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: HorrorColors.crimson),
        actionsIconTheme: const IconThemeData(color: HorrorColors.crimson),
        titleTextStyle: displayFont.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: HorrorColors.crimson,
          letterSpacing: 1.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: HorrorColors.cardSurface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: HorrorColors.darkRedTint, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HorrorColors.bloodRed,
          foregroundColor: HorrorColors.fogWhite,
          disabledBackgroundColor: HorrorColors.cardSurface,
          disabledForegroundColor: HorrorColors.ashGray,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 6,
          shadowColor: HorrorColors.crimson.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: HorrorColors.crimson, width: 1.5),
          ),
          textStyle: bodyFont.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HorrorColors.crimson,
          side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: bodyFont.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HorrorColors.deepSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: bodyFont.copyWith(color: HorrorColors.ashGray),
        labelStyle: bodyFont.copyWith(color: HorrorColors.fogWhite),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: HorrorColors.cardSurface),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: HorrorColors.cardSurface),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: HorrorColors.crimson, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: HorrorColors.crimson, width: 1.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HorrorColors.deepSurface,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
        ),
        titleTextStyle: displayFont.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: HorrorColors.crimson,
        ),
        contentTextStyle: bodyFont.copyWith(
          fontSize: 16,
          color: HorrorColors.fogWhite,
        ),
      ),
    );
  }
}
