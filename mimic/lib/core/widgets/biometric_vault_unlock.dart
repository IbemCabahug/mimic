import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/providers/biometric_providers.dart';
import 'package:mimic/core/services/biometric_service.dart';
import 'package:mimic/core/services/biometric_unlock_store.dart';

class BiometricVaultUnlock extends ConsumerStatefulWidget {
  const BiometricVaultUnlock({
    super.key,
    required this.onUnlockedVault,
    required this.onDecoyAdmin,
    this.onError,
  });

  final void Function(String secret) onUnlockedVault;
  final VoidCallback onDecoyAdmin;
  final void Function(BiometricResult result)? onError;

  @override
  ConsumerState<BiometricVaultUnlock> createState() =>
      _BiometricVaultUnlockState();
}

class _BiometricVaultUnlockState extends ConsumerState<BiometricVaultUnlock> {
  late final BiometricService _service = ref.read(biometricServiceProvider);
  late final BiometricUnlockStore _store =
      ref.read(biometricUnlockStoreProvider);

  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final layer = await _store.activeLayer();
      if (layer == null) {
        widget.onError?.call(BiometricResult.unavailable);
        return;
      }
      final result = await _service.authenticate(reason: 'Unlock');
      if (result != BiometricResult.success) {
        widget.onError?.call(result);
        return;
      }
      
      if (layer == BiometricLayer.vault) {
        final secret = await _store.readSecret(layer);
        if (secret == null) {
          widget.onError?.call(BiometricResult.error);
          return;
        }
        widget.onUnlockedVault(secret);
      } else if (layer == BiometricLayer.admin) {
        widget.onDecoyAdmin();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;
    final isVaultEnabled = ref.watch(biometricEnabledProvider(BiometricLayer.vault)).valueOrNull ?? false;
    final isAdminEnabled = ref.watch(biometricEnabledProvider(BiometricLayer.admin)).valueOrNull ?? false;

    if (!available || (!isVaultEnabled && !isAdminEnabled)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      iconSize: 56,
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fingerprint),
    );
  }
}
