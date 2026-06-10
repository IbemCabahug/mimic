import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/providers/biometric_providers.dart';
import 'package:mimic/core/services/biometric_service.dart';
import 'package:mimic/core/services/biometric_unlock_store.dart';
import 'package:mimic/core/services/shake_route_detector.dart';

class BiometricVaultUnlock extends ConsumerStatefulWidget {
  const BiometricVaultUnlock({
    super.key,
    required this.onUnlockedVault,
    required this.onUnlockedAdmin,
    this.onError,
    this.showArmedHint = false,
  });

  final void Function(String secret) onUnlockedVault;
  final void Function(String secret) onUnlockedAdmin;
  final void Function(BiometricResult result)? onError;
  final bool showArmedHint;

  @override
  ConsumerState<BiometricVaultUnlock> createState() =>
      _BiometricVaultUnlockState();
}

class _BiometricVaultUnlockState extends ConsumerState<BiometricVaultUnlock> {
  final ShakeRouteDetector _shake = ShakeRouteDetector();
  late final BiometricService _service = ref.read(biometricServiceProvider);
  late final BiometricUnlockStore _store =
      ref.read(biometricUnlockStoreProvider);

  bool _busy = false;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _shake.onArmedChanged = (armed) {
      if (mounted) setState(() => _armed = armed);
    };
    _shake.start();
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final goAdmin = _shake.isAdminArmed;
      final layer = goAdmin ? BiometricLayer.admin : BiometricLayer.vault;

      if (!await _store.isEnabled(layer)) {
        widget.onError?.call(BiometricResult.unavailable);
        return;
      }
      final result = await _service.authenticate(reason: 'Unlock');
      if (result != BiometricResult.success) {
        widget.onError?.call(result);
        return;
      }
      final secret = await _store.readSecret(layer);
      if (secret == null) {
        widget.onError?.call(BiometricResult.error);
        return;
      }
      _shake.disarm();
      if (goAdmin) {
        widget.onUnlockedAdmin(secret);
      } else {
        widget.onUnlockedVault(secret);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;
    if (!available) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 56,
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fingerprint),
        ),
        if (widget.showArmedHint && _armed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Admin mode'),
          ),
      ],
    );
  }
}
