import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/security/pin_wipe_service.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/core/services/biometric_unlock_store.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:typed_data';
import 'dart:io';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => store[key];
  @override
  Future<void> secureWrite(String key, String value) async => store[key] = value;
  @override
  Future<void> secureDelete(String key) async => store.remove(key);
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

class FakeKeystoreService implements KeystoreService {
  bool deleted = false;
  @override
  Future<void> ensureKey() async {}
  @override
  Future<String> wrap(String base64Data) async => base64Data;
  @override
  Future<String> unwrap(String base64Data) async => base64Data;
  @override
  Future<void> deleteKey() async => deleted = true;
}

class FakeBiometricUnlockStore implements BiometricUnlockStore {
  bool wiped = false;
  
  @override
  Future<BiometricLayer?> activeLayer() async => null;
  @override
  Future<void> disable(BiometricLayer layer) async {}
  @override
  Future<void> enable(BiometricLayer layer, String secret) async {}
  @override
  Future<bool> isEnabled(BiometricLayer layer) async => false;
  @override
  Future<String?> readSecret(BiometricLayer layer) async => null;

  @override
  Future<void> wipeAll() async => wiped = true;
}

void main() {
  test('wipePin() clears master_key_wrapped, recovery_blob, and all three lockout keys', () async {
    final fakePlatform = FakePlatformService();
    final fakeKeystore = FakeKeystoreService();
    final fakeBiometric = FakeBiometricUnlockStore();
    final wipeService = PinWipeService(
      fakePlatform,
      keystoreService: fakeKeystore,
      biometricUnlockStore: fakeBiometric,
    );

    // Setup dummy data
    fakePlatform.store['master_key_wrapped'] = 'dummy_master';
    fakePlatform.store['recovery_blob'] = 'dummy_recovery';
    fakePlatform.store['recovery_salt'] = 'dummy_salt';
    fakePlatform.store['lockout_set_wall'] = '123';
    fakePlatform.store['lockout_set_elapsed'] = '123';
    fakePlatform.store['lockout_duration_ms'] = '123';
    fakePlatform.store['vault_pin_hash'] = 'hash';

    await wipeService.wipePin();

    expect(fakePlatform.store['master_key_wrapped'], isNull);
    expect(fakePlatform.store['recovery_blob'], isNull);
    expect(fakePlatform.store['recovery_salt'], isNull);
    expect(fakePlatform.store['lockout_set_wall'], isNull);
    expect(fakePlatform.store['lockout_set_elapsed'], isNull);
    expect(fakePlatform.store['lockout_duration_ms'], isNull);
    expect(fakePlatform.store['vault_pin_hash'], isNull);
    
    expect(fakeKeystore.deleted, isTrue);
    expect(fakePlatform.store['vault_wiped'], 'true');
  });
}
