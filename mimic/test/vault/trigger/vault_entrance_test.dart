// test/vault/trigger/vault_entrance_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/trigger/gesture_store.dart';
import 'package:mimic/vault/trigger/vault_entrance.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};
  int readCount = 0;
  int recordReadCount = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCount++;
    if (key == 'vault_gesture_record') {
      recordReadCount++;
    }
    return _data[key];
  }

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
    fakeStorage.recordReadCount = 0;
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

    test('J1: vault exists, gesture [1, 0, 1] stored. Calling verify twice caches positive result without reading salt (first verify: 2 record reads, second: 1)', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      fakeStorage.recordReadCount = 0;
      saltReadCount = 0;

      final entrance = createEntrance();
      final result1 = await entrance.verify([1, 0, 1]);
      final result2 = await entrance.verify([1, 0, 1]);
      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(saltReadCount, equals(0));
      expect(fakeStorage.recordReadCount, equals(3)); // first verify: 2 reads (hasGesture + verifyGesture); second verify: 1 read (cached)
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
      expect(saltReadCount, equals(1)); // salt is NOT read because hasGesture is true and sets cache

      final gestureResult = await entrance.verify([1, 0, 1]);
      expect(gestureResult, isTrue); // stored gesture works
      expect(saltReadCount, equals(1)); // cache was used (no salt read)
    });

    test(
      'M4: vault exists, gesture record present: verify counts storage reads and asserts vault_salt was NEVER read on the happy path',
      () async {
        currentSalt = 'some_base64_salt';
        await store.setGesture([1, 0, 1]);

        fakeStorage.readCount = 0;
        saltReadCount = 0;

        final entrance = createEntrance();
        final result1 = await entrance.verify([1, 0, 1]);

        expect(result1, isTrue);
        expect(saltReadCount, equals(0)); // vault_salt was NEVER read on the happy path
        expect(fakeStorage.readCount, equals(2)); // hasGesture (1) + verifyGesture (1)

        fakeStorage.readCount = 0;
        final result2 = await entrance.verify([1, 0, 1]);
        expect(result2, isTrue);
        expect(saltReadCount, equals(0));
        expect(fakeStorage.readCount, equals(1)); // cached entrance delegates directly to verifyGesture (1 read)
      },
    );

    test('O1: gesture stored. Call prewarm(), then verify the correct gesture. Expected recordReadCount is 2 (1 prewarm + 1 verify), saltReadCount is 0', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      fakeStorage.recordReadCount = 0;
      saltReadCount = 0;

      final entrance = createEntrance();
      await entrance.prewarm();

      // Derivation:
      // 1. prewarm() calls hasGesture() -> 1 record read, sets _vaultExistsCached = true.
      // 2. verify([1, 0, 1]) sees _vaultExistsCached == true -> delegates directly to verifyGesture -> 1 record read.
      // Total recordReadCount = 1 + 1 = 2.
      // vault_salt is never read because hasGesture was true -> saltReadCount = 0.
      final result = await entrance.verify([1, 0, 1]);
      expect(result, isTrue);
      expect(saltReadCount, equals(0));
      expect(fakeStorage.recordReadCount, equals(2));
    });

    test('O2: gesture stored. Call prewarm() twice, then verify. Assert the second prewarm performed zero extra reads', () async {
      currentSalt = 'some_base64_salt';
      await store.setGesture([1, 0, 1]);
      fakeStorage.recordReadCount = 0;
      saltReadCount = 0;

      final entrance = createEntrance();
      await entrance.prewarm();
      expect(fakeStorage.recordReadCount, equals(1)); // first prewarm: hasGesture (1)

      await entrance.prewarm();
      expect(fakeStorage.recordReadCount, equals(1)); // second prewarm: returns immediately with 0 reads

      final result = await entrance.verify([1, 0, 1]);
      expect(result, isTrue);
      expect(saltReadCount, equals(0));
      expect(fakeStorage.recordReadCount, equals(2)); // verify: verifyGesture (1)
    });

    test('O3: no vault and no gesture. Call prewarm(), then confirm setup passage [0, 2, 1] returns true and wrong sequence returns false (prewarm does not poison cache)', () async {
      currentSalt = null;
      fakeStorage.recordReadCount = 0;
      saltReadCount = 0;

      final entrance = createEntrance();
      await entrance.prewarm();

      // prewarm called hasGesture() which returned false -> _vaultExistsCached stays false.
      final passageResult = await entrance.verify(VaultEntrance.setupPassage);
      expect(passageResult, isTrue);
      expect(saltReadCount, equals(1)); // salt read on passage verification

      final wrongResult = await entrance.verify([1, 1, 0]);
      expect(wrongResult, isFalse);
      expect(saltReadCount, equals(2)); // salt read again because negative result is not cached
    });
  });
}
