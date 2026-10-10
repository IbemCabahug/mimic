// lib/game/services/game_skin_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GameSkinId {
  voidHorror,
  vhsGlitch1986,
  bloodMoonEclipse,
  retroCrtGreen,
}

class GameSkinPalette {
  final GameSkinId id;
  final String name;
  final String description;
  final bool isProOnly;
  final Color scaffoldBackground;
  final Color deepSurface;
  final Color cardSurface;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color darkTint;
  final Color textColor;
  final Color subtextColor;

  const GameSkinPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.isProOnly,
    required this.scaffoldBackground,
    required this.deepSurface,
    required this.cardSurface,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.darkTint,
    required this.textColor,
    required this.subtextColor,
  });

  ThemeData toThemeData() {
    final displayFont = GoogleFonts.creepster();
    final bodyFont = GoogleFonts.inter();

    final textTheme = TextTheme(
      displayLarge: displayFont.copyWith(color: textColor),
      displayMedium: displayFont.copyWith(color: textColor),
      displaySmall: displayFont.copyWith(color: textColor),
      headlineLarge: displayFont.copyWith(color: textColor),
      headlineMedium: displayFont.copyWith(color: textColor),
      headlineSmall: displayFont.copyWith(color: textColor),
      titleLarge: displayFont.copyWith(color: textColor),
      titleMedium: displayFont.copyWith(color: textColor),
      titleSmall: displayFont.copyWith(color: textColor),
      bodyLarge: bodyFont.copyWith(color: textColor),
      bodyMedium: bodyFont.copyWith(color: textColor),
      bodySmall: bodyFont.copyWith(color: subtextColor),
      labelLarge: bodyFont.copyWith(color: textColor),
      labelMedium: bodyFont.copyWith(color: textColor),
      labelSmall: bodyFont.copyWith(color: subtextColor),
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardSurface,
      primaryColor: primaryAccent,
      colorScheme: ColorScheme.dark(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: deepSurface,
        error: primaryAccent,
      ),
      textTheme: textTheme,
      fontFamily: bodyFont.fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryAccent),
        actionsIconTheme: IconThemeData(color: primaryAccent),
        titleTextStyle: displayFont.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: primaryAccent,
          letterSpacing: 1.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: darkTint, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryAccent,
          foregroundColor: textColor,
          disabledBackgroundColor: cardSurface,
          disabledForegroundColor: subtextColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 6,
          shadowColor: primaryAccent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: primaryAccent, width: 1.5),
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
          foregroundColor: primaryAccent,
          side: BorderSide(color: secondaryAccent, width: 1.5),
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
        fillColor: deepSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: bodyFont.copyWith(color: subtextColor),
        labelStyle: bodyFont.copyWith(color: textColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cardSurface),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cardSurface),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primaryAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primaryAccent, width: 1.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: deepSurface,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: secondaryAccent, width: 1.5),
        ),
        titleTextStyle: displayFont.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: primaryAccent,
        ),
        contentTextStyle: bodyFont.copyWith(
          fontSize: 16,
          color: textColor,
        ),
      ),
    );
  }
}

class GameSkinPresets {
  static const GameSkinPalette voidHorror = GameSkinPalette(
    id: GameSkinId.voidHorror,
    name: 'Void Horror',
    description: 'Original ominous crimson, ash gray, and deep void black.',
    isProOnly: false,
    scaffoldBackground: Color(0xFF080A0F),
    deepSurface: Color(0xFF0D1117),
    cardSurface: Color(0xFF1A1F2E),
    primaryAccent: Color(0xFFC41E3A),
    secondaryAccent: Color(0xFF8B0000),
    darkTint: Color(0xFF2D1B1B),
    textColor: Color(0xFFE8E0D0),
    subtextColor: Color(0xFF6B7280),
  );

  static const GameSkinPalette vhsGlitch1986 = GameSkinPalette(
    id: GameSkinId.vhsGlitch1986,
    name: 'VHS Glitch 1986',
    description: 'Analog synthwave dread with electric cyan and neon magenta.',
    isProOnly: true,
    scaffoldBackground: Color(0xFF0C0814),
    deepSurface: Color(0xFF130E20),
    cardSurface: Color(0xFF201833),
    primaryAccent: Color(0xFFE02475),
    secondaryAccent: Color(0xFF00E5FF),
    darkTint: Color(0xFF2B1432),
    textColor: Color(0xFFEDE9FE),
    subtextColor: Color(0xFF948BB0),
  );

  static const GameSkinPalette bloodMoonEclipse = GameSkinPalette(
    id: GameSkinId.bloodMoonEclipse,
    name: 'Blood Moon Eclipse',
    description: 'Celestial crimson darkness soaked in dark obsidian and lunar amber.',
    isProOnly: true,
    scaffoldBackground: Color(0xFF0F0505),
    deepSurface: Color(0xFF170808),
    cardSurface: Color(0xFF240E0E),
    primaryAccent: Color(0xFFFF2A2A),
    secondaryAccent: Color(0xFFFF8400),
    darkTint: Color(0xFF381010),
    textColor: Color(0xFFFDE8E8),
    subtextColor: Color(0xFFA87E7E),
  );

  static const GameSkinPalette retroCrtGreen = GameSkinPalette(
    id: GameSkinId.retroCrtGreen,
    name: 'Retro CRT Green',
    description: 'Terminal phosphor green monochrome horror from cold surveillance monitors.',
    isProOnly: true,
    scaffoldBackground: Color(0xFF040A06),
    deepSurface: Color(0xFF08140B),
    cardSurface: Color(0xFF0E2214),
    primaryAccent: Color(0xFF22C55E),
    secondaryAccent: Color(0xFF15803D),
    darkTint: Color(0xFF0B2914),
    textColor: Color(0xFFDCFCE7),
    subtextColor: Color(0xFF65A30D),
  );

  static const List<GameSkinPalette> all = [
    voidHorror,
    vhsGlitch1986,
    bloodMoonEclipse,
    retroCrtGreen,
  ];

  static GameSkinPalette getById(GameSkinId id) {
    return all.firstWhere((p) => p.id == id, orElse: () => voidHorror);
  }

  static GameSkinPalette getByIdString(String idStr) {
    return all.firstWhere((p) => p.id.name == idStr, orElse: () => voidHorror);
  }
}

class GameSkinNotifier extends StateNotifier<GameSkinPalette> {
  static const String _prefKey = 'active_game_skin_id';

  GameSkinNotifier() : super(GameSkinPresets.voidHorror) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      state = GameSkinPresets.getByIdString(saved);
    }
  }

  Future<bool> setSkin(GameSkinPalette palette, {required bool isPro}) async {
    if (palette.isProOnly && !isPro) {
      return false;
    }
    state = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, palette.id.name);
    return true;
  }
}

final gameSkinProvider =
    StateNotifierProvider<GameSkinNotifier, GameSkinPalette>((ref) {
  return GameSkinNotifier();
});

final gameThemeDataProvider = Provider<ThemeData>((ref) {
  final skin = ref.watch(gameSkinProvider);
  return skin.toThemeData();
});
