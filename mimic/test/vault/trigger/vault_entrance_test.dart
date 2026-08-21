// test/vault/trigger/vault_entrance_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/trigger/gesture_store.dart';
import 'package:mimic/vault/trigger/vault_entrance.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late GestureStore store;
  String? currentSalt;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    store = GestureStore(storage: fakeStorage);
    currentSalt = null;
  });

  VaultEntrance createEntrance() {
    return VaultEntrance(
      readVaultSalt: () async => currentSalt,
      store: store,
    );
  }

  group('VaultEntrance', () {
    test('E1: no vault (salt null), taps == setupPassage -> true', () async {
      currentSalt = null;
      final entrance = createEntrance();
      final result = await entrance.verify(VaultEntrance.setupPassage);
      expect(result, isTrue);
    });

    test('E2: no vault (salt null), taps != setupPassage -> false', () async {
      currentSalt = null;
      final entrance = createEntrance();
      final result = await entrance.verify([1, 1, 0]);
      expect(result, isFalse);
    });

    test('E3: salt is the empty string, taps == setupPassage -> true', () async {
      currentSalt = '';
      final entrance = createEntrance();
      final result = await entrance.verify(VaultEntrance.setupPassage);
      expect(result, isTrue);
    });

    test('E4: vault exists, gesture [1, 0, 1] stored, taps [1, 0, 1] -> true', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      final entrance = createEntrance();
      final result = await entrance.verify([1, 0, 1]);
      expect(result, isTrue);
    });

    test('E5: vault exists, gesture [1, 0, 1] stored, taps [2, 0, 2] -> false (proves old published sequence is dead)', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      final entrance = createEntrance();
      final result = await entrance.verify([2, 0, 2]);
      expect(result, isFalse);
    });

    test('E6: vault exists, NO gesture stored, taps == setupPassage -> false (proves passage is permanently dead once vault exists)', () async {
      currentSalt = 'some_base64_salt';
      final entrance = createEntrance();
      final result = await entrance.verify(VaultEntrance.setupPassage);
      expect(result, isFalse);
    });
  });
}
