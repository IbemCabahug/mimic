import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/services/biometric_service.dart';
import 'package:mimic/core/services/biometric_unlock_store.dart';

final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());

final biometricUnlockStoreProvider =
    Provider<BiometricUnlockStore>((ref) => BiometricUnlockStore());

final biometricAvailableProvider = FutureProvider<bool>(
  (ref) => ref.read(biometricServiceProvider).isAvailable(),
);

final biometricEnabledProvider =
    FutureProvider.family<bool, BiometricLayer>(
  (ref, layer) => ref.read(biometricUnlockStoreProvider).isEnabled(layer),
);
