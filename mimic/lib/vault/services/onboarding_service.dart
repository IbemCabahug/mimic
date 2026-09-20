import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingComplete = 'onboarding_complete';

// F30: the in-vault field manual flag. The key name is deliberately
// game-flavoured (the game already ships a tutorial and case files), so
// plaintext SharedPreferences never hint that a hidden vault exists.
const _kVaultManualSeen = 'field_manual_seen';

class OnboardingService {
  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingComplete) ?? false;
  }

  Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingComplete, true);
  }

  /// Whether the vault field manual has been acknowledged. Only read from
  /// inside the vault, after a successful unlock — never from the game UI.
  Future<bool> isVaultManualSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kVaultManualSeen) ?? false;
  }

  /// Marks the manual acknowledged. Idempotent; safe to call from every
  /// dismissal path (GOT IT, back button, swipe).
  Future<void> markVaultManualSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVaultManualSeen, true);
  }
}

final onboardingServiceProvider = Provider<OnboardingService>(
  (_) => OnboardingService(),
);
