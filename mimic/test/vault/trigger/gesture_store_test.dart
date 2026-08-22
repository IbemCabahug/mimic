// test/vault/trigger/gesture_store_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/trigger/gesture_store.dart';

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

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map.unmodifiable(_data);
}

void main() {
  group('GestureStore', () {
    late FakeFlutterSecureStorage fakeStorage;
    late GestureStore store;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      store = GestureStore(storage: fakeStorage);
    });

    test('hasGesture() and verifyGesture() return false before anything is stored', () async {
      expect(await store.hasGesture(), isFalse);
      expect(await store.verifyGesture([1, 0, 2]), isFalse);
    });

    test('setGesture() validates length bounds and rejects all-identical elements', () async {
      // Too short (< 3)
      expect(() => store.setGesture([1, 0]), throwsArgumentError);

      // Too long (> 3)
      expect(
        () => store.setGesture([1, 0, 2, 1]),
        throwsArgumentError,
      );

      // Negative element
      expect(() => store.setGesture([1, -1, 2]), throwsArgumentError);

      // Element above maxZoneIndex (2)
      expect(() => store.setGesture([1, 3, 0]), throwsArgumentError);

      // All elements identical
      expect(() => store.setGesture([2, 2, 2]), throwsArgumentError);
      expect(() => store.setGesture([0, 0, 0]), throwsArgumentError);

      // Nothing was stored
      expect(await store.hasGesture(), isFalse);
    });

    test(
      'stores salted verifier without exposing raw gesture, verifies matching and non-matching gestures, and clearGesture() removes it',
      () async {
        const gesture = [1, 0, 2];

        // 1. Set gesture (Derivation 1)
        await store.setGesture(gesture);
        expect(await store.hasGesture(), isTrue);

        // 2. verifyGesture with identical gesture returns true (Derivation 2)
        expect(await store.verifyGesture([1, 0, 2]), isTrue);

        // 3. verifyGesture with different gesture of same length returns false (Derivation 3)
        expect(await store.verifyGesture([0, 1, 2]), isFalse);

        // 4. verifyGesture with prefix of wrong length returns false (Derivation 4)
        expect(await store.verifyGesture([1, 0]), isFalse);

        // 5. Assert raw gesture is not stored in plainly recoverable form
        final storedVerifier = await fakeStorage.read(
          key: 'vault_gesture_verifier',
        );
        final storedSalt = await fakeStorage.read(key: 'vault_gesture_salt');

        expect(storedVerifier, isNotNull);
        expect(storedSalt, isNotNull);

        // Must start with v3:
        expect(storedVerifier!.startsWith('v3:100000:'), isTrue);

        // Stored verifier must not contain concatenated digits, join with separator, or toString()
        expect(storedVerifier.contains(gesture.join(',')), isFalse);
        expect(storedVerifier.contains(gesture.join('')), isFalse);
        expect(storedVerifier == gesture.toString(), isFalse);

        // Salt must not contain the gesture
        expect(storedSalt!.contains(gesture.join(',')), isFalse);
        expect(storedSalt.contains(gesture.join('')), isFalse);

        // 6. clearGesture removes stored keys
        await store.clearGesture();
        expect(await store.hasGesture(), isFalse);
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
        expect(await store.verifyGesture([1, 0, 2]), isFalse);
      },
    );

    test(
      'setting the same gesture twice produces different salts and verifiers while verifying correctly',
      () async {
        const gesture = [2, 1, 0];

        // First set (Derivation 5)
        await store.setGesture(gesture);
        final verifier1 = await fakeStorage.read(key: 'vault_gesture_verifier');
        final salt1 = await fakeStorage.read(key: 'vault_gesture_salt');

        // Second set of identical gesture (Derivation 6)
        await store.setGesture(gesture);
        final verifier2 = await fakeStorage.read(key: 'vault_gesture_verifier');
        final salt2 = await fakeStorage.read(key: 'vault_gesture_salt');

        // Salts and verifiers must be distinct
        expect(salt1, isNotNull);
        expect(salt2, isNotNull);
        expect(salt1 != salt2, isTrue);
        expect(verifier1, isNotNull);
        expect(verifier2, isNotNull);
        expect(verifier1 != verifier2, isTrue);

        // Must still verify correctly (Derivation 7)
        expect(await store.verifyGesture([2, 1, 0]), isTrue);
      },
    );

    test(
      'gestureLength() tracks stored gesture length and hasGesture() requires all three keys (verifier, salt, length)',
      () async {
        // Initial state before any gesture is stored
        expect(await store.gestureLength(), isNull);

        // Set a 3-tap gesture (Derivation 8)
        const threeTapGesture = [1, 0, 2];
        await store.setGesture(threeTapGesture);

        // gestureLength returns 3 and hasGesture is true
        expect(await store.gestureLength(), equals(3));
        expect(await store.hasGesture(), isTrue);

        final savedVerifier = await fakeStorage.read(
          key: 'vault_gesture_verifier',
        );
        final savedSalt = await fakeStorage.read(key: 'vault_gesture_salt');
        expect(
          await fakeStorage.read(key: 'vault_gesture_length'),
          equals('3'),
        );

        // Incomplete state 1: verifier and salt present, but length key deleted directly from fake
        await fakeStorage.delete(key: 'vault_gesture_length');
        expect(await store.hasGesture(), isFalse);
        expect(await store.gestureLength(), isNull);

        // Incomplete state 2: length and salt present, but verifier deleted directly from fake
        await fakeStorage.write(key: 'vault_gesture_length', value: '3');
        await fakeStorage.delete(key: 'vault_gesture_verifier');
        expect(await store.hasGesture(), isFalse);

        // Restore verifier to full valid state
        await fakeStorage.write(
          key: 'vault_gesture_verifier',
          value: savedVerifier,
        );
        expect(await store.hasGesture(), isTrue);
        expect(await store.gestureLength(), equals(3));

        // clearGesture removes all three keys and gestureLength returns null
        await store.clearGesture();
        expect(await store.hasGesture(), isFalse);
        expect(await store.gestureLength(), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_length'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
      },
    );

    test(
      'K1: verifyGesture returns false early when length key is deleted from storage',
      () async {
        const gesture = [1, 0, 1];
        // Store a gesture (Derivation 9)
        await store.setGesture(gesture);

        // Delete ONLY the length key from fake storage
        await fakeStorage.delete(key: 'vault_gesture_length');

        // verifyGesture([1, 0, 1]) -> false (early null return before PBKDF2 derivation)
        expect(await store.verifyGesture([1, 0, 1]), isFalse);
      },
    );
  });
}
