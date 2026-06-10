// mimic/lib/vault/security/pin_wipe_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/biometric_unlock_store.dart';

class PinWipeService {
  final PlatformService _platformService;
  final BiometricUnlockStore _biometricUnlockStore;

  PinWipeService(this._platformService, {BiometricUnlockStore? biometricUnlockStore})
      : _biometricUnlockStore = biometricUnlockStore ?? BiometricUnlockStore();

  Future<void> wipePin() async {
    if (kIsWeb) return;
    await _platformService.secureDelete('vault_pin_hash');
    await _platformService.secureDelete('vault_pin_salt');
    await _platformService.secureDelete('vault_pin');
    await _platformService.secureDelete('wrong_attempts');
    await _biometricUnlockStore.wipeAll();
  }

  Future<bool> isPinWiped() async {
    if (kIsWeb) return false;
    final hash = await _platformService.secureRead('vault_pin_hash');
    return hash == null;
  }
}

final pinWipeServiceProvider = Provider<PinWipeService>((ref) {
  return PinWipeService(ref.read(platformServiceProvider));
});
