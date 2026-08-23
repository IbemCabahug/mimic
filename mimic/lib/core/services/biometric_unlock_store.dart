import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';

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

const String _bioPrefix = 'bio1:';

class BiometricUnlockStore {
  BiometricUnlockStore({
    FlutterSecureStorage? storage,
    BiometricKeystoreService? keystore,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _keystore = keystore ?? AndroidKeystoreService();

  final FlutterSecureStorage _storage;
  final BiometricKeystoreService _keystore;

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

  Future<void> writeBioSecret(String secret) async {
    await _keystore.ensureBioKey();
    final wrapped = await _keystore.bioWrap(base64Encode(utf8.encode(secret)));
    await _storage.write(key: BiometricLayer.vault.secretKey, value: _bioPrefix + wrapped);
    await _storage.write(key: BiometricLayer.vault.enabledKey, value: 'true');
  }

  Future<String?> readBioSecret() async {
    if (!await isEnabled(BiometricLayer.vault)) return null;
    final stored = await _storage.read(key: BiometricLayer.vault.secretKey);
    if (stored == null) return null;
    if (!stored.startsWith(_bioPrefix)) {
      await _storage.delete(key: BiometricLayer.vault.secretKey);
      await _storage.write(key: BiometricLayer.vault.enabledKey, value: 'false');
      return null;
    }
    final blob = stored.substring(_bioPrefix.length);
    final unwrapped = await _keystore.bioUnwrap(blob);
    return utf8.decode(base64Decode(unwrapped));
  }

  Future<void> clearBioSecret() async {
    await _storage.delete(key: BiometricLayer.vault.secretKey);
    await _storage.write(key: BiometricLayer.vault.enabledKey, value: 'false');
    try {
      await _keystore.deleteBioKey();
    } on BiometricKeyInvalidatedException {
      // Key already invalidated is treated as successfully cleared.
    }
  }

  Future<bool> hasBioSecret() async {
    if (!await isEnabled(BiometricLayer.vault)) return false;
    final stored = await _storage.read(key: BiometricLayer.vault.secretKey);
    return stored != null && stored.startsWith(_bioPrefix);
  }
}
