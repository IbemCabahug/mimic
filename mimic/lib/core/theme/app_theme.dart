import 'package:flutter/material.dart';

/// Game theme - dark theme for the social deduction game facade
final ThemeData gameTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0F0F14), // Dark background #0F0F14
  primaryColor: const Color(0xFF7F77DD), // Primary color #7F77DD
  colorScheme: ColorScheme.dark(
    primary: const Color(0xFF7F77DD), // Primary #7F77DD
    secondary: const Color(0xFF1D9E75), // Accent #1D9E75
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 16),
    bodyMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 14),
    bodySmall: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 12),
    titleLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.bold),
    titleSmall: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 16, fontWeight: FontWeight.bold),
  ),
  fontFamily: 'SpaceGrotesk',
);

/// Vault theme - light theme for the encrypted vault
final ThemeData vaultTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFFFFFFF), // White background #FFFFFF
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF534AB7), // Accent #534AB7
    surface: Color(0xFFF1EFE8), // Surface #F1EFE8
    error: Color(0xFFD85A30),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: Color(0xFF534AB7)),
    actionsIconTheme: IconThemeData(color: Color(0xFF534AB7)),
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Color(0xFF534AB7),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF1EFE8),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF534AB7), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD85A30), width: 1),
    ),
    labelStyle: const TextStyle(fontFamily: 'Inter', color: Color(0xFF6B6B6B)),
    hintStyle: const TextStyle(fontFamily: 'Inter', color: Color(0xFF8E8E8E)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF534AB7),
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  ),
  cardTheme: const CardThemeData(
    color: Color(0xFFF1EFE8),
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF1A1A1A),
    actionTextColor: Color(0xFF534AB7),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    contentTextStyle: TextStyle(
      fontFamily: 'Inter',
      color: Colors.white,
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xFF534AB7),
    foregroundColor: Colors.white,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: Colors.white,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Color(0xFF1A1A1A),
    ),
    contentTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      color: Color(0xFF6B6B6B),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    horizontalTitleGap: 8,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Color(0xFF1A1A1A)),
    bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0xFF1A1A1A)),
    bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF1A1A1A)),
    titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    titleSmall: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    headlineLarge: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
    labelMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1A1A1A)),
  ),
  fontFamily: 'Inter',
);

/// Vault color palette constants
class VaultColors {
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF1EFE8);
  static const accent = Color(0xFF534AB7);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B6B6B);
  static const textTertiary = Color(0xFF8E8E8E);
  static const error = Color(0xFFD85A30);
  static const success = Color(0xFF1D9E75);
}

/// Export both themes for use in their respective modules
/// Game module should only use gameTheme
/// Vault module should only use vaultTheme
/// Never mix these themes between modules as per requirements

