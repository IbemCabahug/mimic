// lib/core/services/launcher_icon_service.dart

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LauncherIconService {
  static const MethodChannel _channel = MethodChannel('mimic/launcher_icon');

  Future<bool> isIconVisible() async {
    try {
      final result = await _channel.invokeMethod<bool>('isIconVisible');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setIconVisible(bool visible) async {
    try {
      await _channel.invokeMethod('setIconVisible', {'visible': visible});
    } catch (_) {}
  }
}

class LauncherIconNotifier extends StateNotifier<bool> {
  LauncherIconNotifier(this._service) : super(true) {
    _load();
  }

  final LauncherIconService _service;

  Future<void> _load() async {
    final visible = await _service.isIconVisible();
    state = visible;
  }

  Future<void> setIconVisible(bool visible) async {
    await _service.setIconVisible(visible);
    state = visible;
  }
}

final launcherIconServiceProvider = Provider<LauncherIconService>(
  (ref) => LauncherIconService(),
);

final launcherIconProvider = StateNotifierProvider<LauncherIconNotifier, bool>(
  (ref) => LauncherIconNotifier(ref.read(launcherIconServiceProvider)),
);
