// test/game/services/game_skin_service_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/services/game_skin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GameSkinService tests', () {
    test('default skin is Void Horror', () {
      final notifier = GameSkinNotifier();
      expect(notifier.state.id, GameSkinId.voidHorror);
      expect(notifier.state.name, 'Void Horror');
      expect(notifier.state.isProOnly, isFalse);
    });

    test('non-pro user cannot select pro skins', () async {
      final notifier = GameSkinNotifier();
      final success = await notifier.setSkin(
        GameSkinPresets.vhsGlitch1986,
        isPro: false,
      );

      expect(success, isFalse);
      expect(notifier.state.id, GameSkinId.voidHorror);
    });

    test('pro user can select pro skins and persist preference', () async {
      final notifier = GameSkinNotifier();
      final success = await notifier.setSkin(
        GameSkinPresets.retroCrtGreen,
        isPro: true,
      );

      expect(success, isTrue);
      expect(notifier.state.id, GameSkinId.retroCrtGreen);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_game_skin_id'), GameSkinId.retroCrtGreen.name);
    });

    test('free skins can be selected without pro entitlement', () async {
      final notifier = GameSkinNotifier();
      final success = await notifier.setSkin(
        GameSkinPresets.voidHorror,
        isPro: false,
      );

      expect(success, isTrue);
      expect(notifier.state.id, GameSkinId.voidHorror);
    });

    test('palette produces valid dark ThemeData', () {
      for (final skin in GameSkinPresets.all) {
        final theme = skin.toThemeData();
        expect(theme.brightness, Brightness.dark);
        expect(theme.primaryColor, skin.primaryAccent);
        expect(theme.scaffoldBackgroundColor, skin.scaffoldBackground);
      }
    });
  });
}
