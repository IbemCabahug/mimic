// test/vault/services/onboarding_service_test.dart
//
// F30 tests for the two onboarding flags: the game's first-run onboarding and
// the vault field manual. They share one service and one SharedPreferences
// store, and the keys must stay independent of each other — a manual read from
// inside the vault must never change the game's onboarding state, and vice
// versa. No device, no plugins beyond the in-memory prefs mock.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/vault/services/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F30 · OnboardingService', () {
    late OnboardingService service;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = OnboardingService();
    });

    test('manual starts unread on a fresh install', () async {
      expect(await service.isVaultManualSeen(), isFalse);
    });

    test('markVaultManualSeen flips the flag, and it stays flipped', () async {
      await service.markVaultManualSeen();
      expect(await service.isVaultManualSeen(), isTrue);

      // A second acknowledgement (back button after GOT IT, say) is a no-op,
      // never a toggle back to unread.
      await service.markVaultManualSeen();
      expect(await service.isVaultManualSeen(), isTrue);
    });

    test('the manual flag survives a fresh service instance (new provider)', () async {
      await service.markVaultManualSeen();
      expect(await OnboardingService().isVaultManualSeen(), isTrue);
    });

    test('the manual flag is independent of the game onboarding flag', () async {
      // Game onboarding completed first: the manual must still be unread.
      await service.markOnboardingComplete();
      expect(await service.isOnboardingComplete(), isTrue);
      expect(await service.isVaultManualSeen(), isFalse);

      // Now acknowledge the manual: onboarding must be untouched.
      await service.markVaultManualSeen();
      expect(await service.isVaultManualSeen(), isTrue);
      expect(await service.isOnboardingComplete(), isTrue);
    });

    test('the persisted keys are game-flavoured, never vault-flavoured', () async {
      await service.markVaultManualSeen();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Plaintext SharedPreferences must not spell out that a hidden vault
      // exists; the flag reads as an ordinary game guide popup.
      expect(keys, contains('field_manual_seen'));
      expect(keys, isNot(contains('vault_manual_seen')));
      for (final key in keys) {
        expect(key.toLowerCase(), isNot(contains('vault')));
      }
    });
  });
}
