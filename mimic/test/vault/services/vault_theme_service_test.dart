import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/vault/services/vault_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultThemeService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default palette is classic light theme', () {
      final notifier = VaultThemeNotifier();
      expect(notifier.state.id, equals(VaultThemeId.classic));
      expect(notifier.state.brightness, equals(Brightness.light));
      expect(notifier.state.isProOnly, isFalse);
    });

    test('gating: non-Pro users cannot activate Pro-only themes', () async {
      final notifier = VaultThemeNotifier();

      final oledResult = await notifier.setTheme(VaultThemeId.oled, isPro: false);
      expect(oledResult, isFalse);
      expect(notifier.state.id, equals(VaultThemeId.classic));

      final hackerResult = await notifier.setTheme(VaultThemeId.hacker, isPro: false);
      expect(hackerResult, isFalse);
      expect(notifier.state.id, equals(VaultThemeId.classic));
    });

    test('Pro users can activate any Pro-only theme', () async {
      final notifier = VaultThemeNotifier();

      final oledResult = await notifier.setTheme(VaultThemeId.oled, isPro: true);
      expect(oledResult, isTrue);
      expect(notifier.state.id, equals(VaultThemeId.oled));
      expect(notifier.state.background, equals(VaultThemeService.oled.background));

      final hackerResult = await notifier.setTheme(VaultThemeId.hacker, isPro: true);
      expect(hackerResult, isTrue);
      expect(notifier.state.id, equals(VaultThemeId.hacker));
      expect(notifier.state.accent, equals(VaultThemeService.hacker.accent));
    });

    test('theme palettes produce valid ThemeData', () {
      for (final palette in VaultThemeService.allThemes) {
        final themeData = palette.toThemeData();
        expect(themeData.brightness, equals(palette.brightness));
        expect(themeData.scaffoldBackgroundColor, equals(palette.background));
        expect(themeData.primaryColor, equals(palette.accent));
      }
    });
  });
}
