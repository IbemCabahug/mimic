// lib/core/services/stealth_mode_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StealthModeService {
  static const String _kStealthModeKey = 'stealth_mode_enabled';

  Future<bool> isStealthModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kStealthModeKey) ?? false;
  }

  Future<void> setStealthMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStealthModeKey, value);
  }
}

class StealthModeNotifier extends StateNotifier<bool> {
  StealthModeNotifier(this._service) : super(false) {
    _load();
  }

  final StealthModeService _service;

  Future<void> _load() async {
    final value = await _service.isStealthModeEnabled();
    state = value;
  }

  Future<void> setStealthMode(bool value) async {
    await _service.setStealthMode(value);
    state = value;
  }
}

final stealthModeServiceProvider = Provider<StealthModeService>(
  (ref) => StealthModeService(),
);

final stealthModeProvider = StateNotifierProvider<StealthModeNotifier, bool>(
  (ref) => StealthModeNotifier(ref.read(stealthModeServiceProvider)),
);
