import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum BiometricLayer {
  admin, vault;

  String get code {
    switch (this) {
      case BiometricLayer.admin: return 'admin';
      case BiometricLayer.vault: return 'vault';
    }
  }
}

extension _BiometricLayerKeys on BiometricLayer {
  String get enabledKey => 'biometric_enabled_$code';
  String get secretKey => 'biometric_secret_$code';
}

class BiometricUnlockStore {
  BiometricUnlockStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<bool> isEnabled(BiometricLayer layer) async =>
      (await _storage.read(key: layer.enabledKey)) == 'true';

  Future<void> enable(BiometricLayer layer, String secret) async {
    await _storage.write(key: layer.secretKey, value: secret);
    await _storage.write(key: layer.enabledKey, value: 'true');
  }

  Future<void> disable(BiometricLayer layer) async {
    await _storage.delete(key: layer.secretKey);
    await _storage.write(key: layer.enabledKey, value: 'false');
  }

  Future<String?> readSecret(BiometricLayer layer) async {
    if (!await isEnabled(layer)) return null;
    return _storage.read(key: layer.secretKey);
  }

  Future<BiometricLayer?> activeLayer() async {
    if (await isEnabled(BiometricLayer.vault)) return BiometricLayer.vault;
    if (await isEnabled(BiometricLayer.admin)) return BiometricLayer.admin;
    return null;
  }

  Future<void> wipeAll() async {
    for (final layer in BiometricLayer.values) {
      await disable(layer);
    }
  }
}
