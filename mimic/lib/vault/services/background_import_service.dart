import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BackgroundImportCommand {
  pauseRequested,
  cancelRequested,
  serviceTimedOut,
  serviceStoppedByOs,
}

class BackgroundServiceStartResult {
  final bool started;
  final bool notificationsGranted;
  final String? errorCode;
  final String? safeMessage;

  const BackgroundServiceStartResult({
    required this.started,
    required this.notificationsGranted,
    this.errorCode,
    this.safeMessage,
  });
}

/// Platform bridge between the single app-scoped [ImportCoordinator] and the
/// Android foreground service ([ImportForegroundService]).
abstract class BackgroundImportBridge {
  Future<bool> hasNotificationPermission();

  Future<bool> requestNotificationPermission();

  Future<BackgroundServiceStartResult> startImportService({
    required int completed,
    required int total,
    int? activePercent,
  });

  Future<void> updateImportService({
    required int completed,
    required int total,
    int? activePercent,
  });

  Future<void> stopImportService();

  void setCommandHandler(
    void Function(BackgroundImportCommand command)? handler,
  );

  void dispose();
}

/// Android `MethodChannel` implementation backed by `mimic/import_service`.
///
/// Runs strictly in the single main FlutterEngine / app process so a native
/// service can never spin up a second competing `ImportCoordinator`.
class AndroidBackgroundImportBridge implements BackgroundImportBridge {
  static const MethodChannel _channel = MethodChannel('mimic/import_service');

  void Function(BackgroundImportCommand command)? _commandHandler;
  bool _handlerBound = false;
  bool _disposed = false;

  void _ensureBound() {
    if (_handlerBound || kIsWeb || !Platform.isAndroid) return;
    _handlerBound = true;
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return null;
      if (call.method == 'onServiceEvent') {
        final args = call.arguments as Map<Object?, Object?>?;
        final event = args?['event'] as String?;
        switch (event) {
          case 'pause':
            _commandHandler?.call(BackgroundImportCommand.pauseRequested);
            break;
          case 'cancel':
            _commandHandler?.call(BackgroundImportCommand.cancelRequested);
            break;
          case 'timeout':
            _commandHandler?.call(BackgroundImportCommand.serviceTimedOut);
            break;
          case 'stopped':
            _commandHandler?.call(BackgroundImportCommand.serviceStoppedByOs);
            break;
        }
      }
      return null;
    });
  }

  @override
  void setCommandHandler(
    void Function(BackgroundImportCommand command)? handler,
  ) {
    _commandHandler = handler;
    _ensureBound();
  }

  @override
  Future<bool> hasNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    _ensureBound();
    try {
      final res = await _channel.invokeMethod<bool>(
        'hasNotificationPermission',
      );
      return res ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    _ensureBound();
    try {
      final res = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<BackgroundServiceStartResult> startImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const BackgroundServiceStartResult(
        started: true,
        notificationsGranted: true,
      );
    }
    _ensureBound();
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'startService',
        <String, Object?>{
          'completed': completed,
          'total': total,
          'activePercent': ?activePercent,
        },
      );
      if (res == null) {
        return const BackgroundServiceStartResult(
          started: false,
          notificationsGranted: false,
          errorCode: 'null_response',
          safeMessage: 'Background service did not start.',
        );
      }
      final started = res['started'] as bool? ?? false;
      final notifGranted = res['notificationsGranted'] as bool? ?? true;
      final errorCode = res['errorCode'] as String?;
      final safeMessage = res['safeMessage'] as String?;
      return BackgroundServiceStartResult(
        started: started,
        notificationsGranted: notifGranted,
        errorCode: errorCode,
        safeMessage: safeMessage,
      );
    } on MissingPluginException {
      return const BackgroundServiceStartResult(
        started: false,
        notificationsGranted: false,
        errorCode: 'missing_plugin',
        safeMessage: 'Background service is unavailable.',
      );
    } on PlatformException catch (e) {
      return BackgroundServiceStartResult(
        started: false,
        notificationsGranted: false,
        errorCode: e.code,
        safeMessage: 'Background service could not start.',
      );
    }
  }

  @override
  Future<void> updateImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    if (kIsWeb || !Platform.isAndroid || _disposed) return;
    _ensureBound();
    try {
      await _channel.invokeMethod<void>('updateProgress', <String, Object?>{
        'completed': completed,
        'total': total,
        'activePercent': ?activePercent,
      });
    } catch (_) {}
  }

  @override
  Future<void> stopImportService() async {
    if (kIsWeb || !Platform.isAndroid || _disposed) return;
    _ensureBound();
    try {
      await _channel.invokeMethod<void>('stopService');
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _commandHandler = null;
    if (_handlerBound && !kIsWeb && Platform.isAndroid) {
      try {
        _channel.setMethodCallHandler(null);
      } catch (_) {}
    }
  }
}

/// Deterministic no-op bridge for host/widget tests when Android native code
/// is not present.
class NoopBackgroundImportBridge implements BackgroundImportBridge {
  @override
  Future<bool> hasNotificationPermission() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<BackgroundServiceStartResult> startImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    return const BackgroundServiceStartResult(
      started: true,
      notificationsGranted: true,
    );
  }

  @override
  Future<void> updateImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {}

  @override
  Future<void> stopImportService() async {}

  @override
  void setCommandHandler(
    void Function(BackgroundImportCommand command)? handler,
  ) {}

  @override
  void dispose() {}
}

final backgroundImportBridgeProvider = Provider<BackgroundImportBridge>((ref) {
  final bridge = AndroidBackgroundImportBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});
