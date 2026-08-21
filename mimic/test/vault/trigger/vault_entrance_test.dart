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
  int saltReadCount = 0;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    store = GestureStore(storage: fakeStorage);
    currentSalt = null;
    saltReadCount = 0;
  });

  VaultEntrance createEntrance() {
    return VaultEntrance(
      readVaultSalt: () async {
        saltReadCount++;
        return currentSalt;
      },
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

    test('J1: vault exists, gesture [1, 0, 1] stored. Calling verify twice caches positive result (saltReadCount == 1)', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      final entrance = createEntrance();
      final result1 = await entrance.verify([1, 0, 1]);
      final result2 = await entrance.verify([1, 0, 1]);
      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(saltReadCount, equals(1));
    });

    test('J2: no vault (salt null). Calling verify twice does not cache negative result (saltReadCount == 2)', () async {
      currentSalt = null;
      final entrance = createEntrance();
      final result1 = await entrance.verify(VaultEntrance.setupPassage);
      final result2 = await entrance.verify(VaultEntrance.setupPassage);
      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(saltReadCount, equals(2));
    });

    test('J3: passage dies as soon as a vault appears, even on an object that previously saw no vault', () async {
      currentSalt = null;
      final entrance = createEntrance();
      final initialResult = await entrance.verify(VaultEntrance.setupPassage);
      expect(initialResult, isTrue);
      expect(saltReadCount, equals(1));

      // Now create a vault and store a gesture
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);

      // On the SAME VaultEntrance instance:
      final passageResult = await entrance.verify(VaultEntrance.setupPassage);
      expect(passageResult, isFalse); // passage is dead
      expect(saltReadCount, equals(2)); // salt was read and cached

      final gestureResult = await entrance.verify([1, 0, 1]);
      expect(gestureResult, isTrue); // stored gesture works
      expect(saltReadCount, equals(2)); // cache was used (no 3rd salt read)
    });
  });
}
