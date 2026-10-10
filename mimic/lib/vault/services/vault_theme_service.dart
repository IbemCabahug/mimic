// mimic/lib/vault/services/vault_theme_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VaultThemeId {
  classic,
  oled,
  midnight,
  hacker,
  sepia,
}

class VaultPalette {
  final VaultThemeId id;
  final String name;
  final String description;
  final bool isProOnly;
  final Color background;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Brightness brightness;

  const VaultPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.isProOnly,
    required this.background,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    this.error = const Color(0xFFD85A30),
    this.success = const Color(0xFF1D9E75),
    required this.brightness,
  });

  ThemeData toThemeData() {
    final isDark = brightness == Brightness.dark;
    final interFont = GoogleFonts.inter().fontFamily;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: accent,
        onSecondary: isDark ? Colors.black : Colors.white,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: accent),
        actionsIconTheme: IconThemeData(color: accent),
        titleTextStyle: TextStyle(
          fontFamily: interFont,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      fontFamily: interFont,
    );
  }
}

class VaultThemeService {
  static const String _prefKey = 'vault_theme_id';

  static const VaultPalette classic = VaultPalette(
    id: VaultThemeId.classic,
    name: 'Classic Violet',
    description: 'Crisp light vault with signature violet accents',
    isProOnly: false,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF1EFE8),
    accent: Color(0xFF534AB7),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF6B6B6B),
    brightness: Brightness.light,
  );

  static const VaultPalette oled = VaultPalette(
    id: VaultThemeId.oled,
    name: 'Deep Ocean',
    description: 'Calming navy-blue dark vault — research-proven to reduce stress and build trust',
    isProOnly: true,
    background: Color(0xFF0B1426),
    surface: Color(0xFF121E36),
    accent: Color(0xFF6FA8DC),
    textPrimary: Color(0xFFE8EEF5),
    textSecondary: Color(0xFF8DA4BE),
    brightness: Brightness.dark,
  );

  static const VaultPalette midnight = VaultPalette(
    id: VaultThemeId.midnight,
    name: 'Soft Lavender',
    description: 'Gentle lavender tones — combines blue tranquility with subtle warmth for cortisol reduction',
    isProOnly: true,
    background: Color(0xFFF5F0FA),
    surface: Color(0xFFEAE0F5),
    accent: Color(0xFF7E57C2),
    textPrimary: Color(0xFF2D1B4E),
    textSecondary: Color(0xFF6B5B7B),
    brightness: Brightness.light,
  );

  static const VaultPalette hacker = VaultPalette(
    id: VaultThemeId.hacker,
    name: 'Forest Twilight',
    description: 'Muted forest green — nature tones that restore focus and ease mental fatigue',
    isProOnly: true,
    background: Color(0xFF0D1510),
    surface: Color(0xFF162019),
    accent: Color(0xFF7CB69A),
    textPrimary: Color(0xFFDAE8DF),
    textSecondary: Color(0xFF8FAA98),
    brightness: Brightness.dark,
  );


  static const VaultPalette sepia = VaultPalette(
    id: VaultThemeId.sepia,
    name: 'Vintage Archive',
    description: 'Warm antique parchment and detective casefile leather tones',
    isProOnly: true,
    background: Color(0xFFF4ECD8),
    surface: Color(0xFFE8DDC4),
    accent: Color(0xFF6D4C41),
    textPrimary: Color(0xFF2E1C0C),
    textSecondary: Color(0xFF5D4E3C),
    brightness: Brightness.light,
  );

  static const List<VaultPalette> allThemes = [
    classic,
    oled,
    midnight,
    hacker,
    sepia,
  ];

  static VaultPalette fromId(VaultThemeId id) {
    switch (id) {
      case VaultThemeId.classic:
        return classic;
      case VaultThemeId.oled:
        return oled;
      case VaultThemeId.midnight:
        return midnight;
      case VaultThemeId.hacker:
        return hacker;
      case VaultThemeId.sepia:
        return sepia;
    }
  }

  static VaultPalette fromString(String? str) {
    if (str == null) return classic;
    for (final t in allThemes) {
      if (t.id.name == str) return t;
    }
    return classic;
  }
}

class VaultThemeNotifier extends StateNotifier<VaultPalette> {
  VaultThemeNotifier() : super(VaultThemeService.classic) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idStr = prefs.getString(VaultThemeService._prefKey);
      state = VaultThemeService.fromString(idStr);
    } catch (_) {}
  }

  Future<bool> setTheme(VaultThemeId id, {required bool isPro}) async {
    final palette = VaultThemeService.fromId(id);
    if (palette.isProOnly && !isPro) {
      return false;
    }
    state = palette;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(VaultThemeService._prefKey, id.name);
    } catch (_) {}
    return true;
  }
}

final vaultThemeProvider = StateNotifierProvider<VaultThemeNotifier, VaultPalette>((ref) {
  return VaultThemeNotifier();
});
