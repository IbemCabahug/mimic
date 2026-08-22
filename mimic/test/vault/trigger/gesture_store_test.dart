import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
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
        final record = await fakeStorage.read(key: 'vault_gesture_record');
        expect(record, isNotNull);
        final parts = record!.split('|');
        expect(parts.length, equals(3));
        final storedVerifier = parts[0];
        final storedSalt = parts[1];

        // Must start with v3:
        expect(storedVerifier.startsWith('v3:100000:'), isTrue);

        // Stored verifier must not contain concatenated digits, join with separator, or toString()
        expect(storedVerifier.contains(gesture.join(',')), isFalse);
        expect(storedVerifier.contains(gesture.join('')), isFalse);
        expect(storedVerifier == gesture.toString(), isFalse);

        // Salt must not contain the gesture
        expect(storedSalt.contains(gesture.join(',')), isFalse);
        expect(storedSalt.contains(gesture.join('')), isFalse);

        // All three legacy keys are null after setGesture
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_length'), isNull);

        // 6. clearGesture removes stored keys
        await store.clearGesture();
        expect(await store.hasGesture(), isFalse);
        expect(await fakeStorage.read(key: 'vault_gesture_record'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_length'), isNull);
        expect(await store.verifyGesture([1, 0, 2]), isFalse);
      },
    );

    test(
      'setting the same gesture twice produces different salts and verifiers while verifying correctly',
      () async {
        const gesture = [2, 1, 0];

        // First set (Derivation 5)
        await store.setGesture(gesture);
        final record1 = await fakeStorage.read(key: 'vault_gesture_record');
        expect(record1, isNotNull);
        final parts1 = record1!.split('|');
        expect(parts1.length, equals(3));
        final verifier1 = parts1[0];
        final salt1 = parts1[1];

        // Second set of identical gesture (Derivation 6)
        await store.setGesture(gesture);
        final record2 = await fakeStorage.read(key: 'vault_gesture_record');
        expect(record2, isNotNull);
        final parts2 = record2!.split('|');
        expect(parts2.length, equals(3));
        final verifier2 = parts2[0];
        final salt2 = parts2[1];

        // Salts and verifiers must be distinct
        expect(salt1 != salt2, isTrue);
        expect(verifier1 != verifier2, isTrue);

        // Must still verify correctly (Derivation 7)
        expect(await store.verifyGesture([2, 1, 0]), isTrue);
      },
    );

    test(
      'gestureLength() tracks stored gesture length and hasGesture() requires a valid stored record',
      () async {
        // Initial state before any gesture is stored
        expect(await store.gestureLength(), isNull);

        // Set a 3-tap gesture (Derivation 8)
        const threeTapGesture = [1, 0, 2];
        await store.setGesture(threeTapGesture);

        // gestureLength returns 3 and hasGesture is true
        expect(await store.gestureLength(), equals(3));
        expect(await store.hasGesture(), isTrue);

        final savedRecord = await fakeStorage.read(
          key: 'vault_gesture_record',
        );
        expect(savedRecord, isNotNull);
        final parts = savedRecord!.split('|');
        expect(parts.length, equals(3));
        expect(parts[2], equals('3'));

        // Incomplete/malformed state 1: record deleted directly from fake
        await fakeStorage.delete(key: 'vault_gesture_record');
        expect(await store.hasGesture(), isFalse);
        expect(await store.gestureLength(), isNull);

        // Incomplete/malformed state 2: record has invalid length part
        await fakeStorage.write(
          key: 'vault_gesture_record',
          value: '${parts[0]}|${parts[1]}|not_a_number',
        );
        expect(await store.hasGesture(), isFalse);
        expect(await store.gestureLength(), isNull);

        // Restore record to full valid state
        await fakeStorage.write(
          key: 'vault_gesture_record',
          value: savedRecord,
        );
        expect(await store.hasGesture(), isTrue);
        expect(await store.gestureLength(), equals(3));

        // clearGesture removes record and gestureLength returns null
        await store.clearGesture();
        expect(await store.hasGesture(), isFalse);
        expect(await store.gestureLength(), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_record'), isNull);
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

        // Replace the record with a malformed value (single-part string with no '|')
        await fakeStorage.write(
          key: 'vault_gesture_record',
          value: 'malformed_record_without_separator',
        );

        // verifyGesture([1, 0, 1]) -> false (early null return before PBKDF2 derivation)
        expect(await store.verifyGesture([1, 0, 1]), isFalse);
      },
    );

    test(
      'M1: setGesture writes vault_gesture_record and deletes all three legacy keys, then verifyGesture verifies',
      () async {
        const gesture = [1, 0, 2];
        // Derivation 10 (setGesture) + Derivation 11 (verifyGesture)
        await store.setGesture(gesture);

        expect(await store.verifyGesture(gesture), isTrue);

        final record = await fakeStorage.read(key: 'vault_gesture_record');
        expect(record, isNotNull);
        expect(record!.split('|').length, equals(3));
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_length'), isNull);
      },
    );

    test(
      'M2: legacy 3-key storage migrates on verifyGesture to combined record and deletes legacy keys',
      () async {
        const gesture = [1, 0, 2];
        final passwordBytes = Uint8List.fromList(utf8.encode(gesture.join(',')));
        final saltBytes = Uint8List.fromList(List<int>.generate(16, (i) => i));
        final saltBase64 = base64Encode(saltBytes);

        // Derivation 12 (helper deriving legacy verifier)
        final derivedKey = await derivePbkdf2Async(
          passwordBytes,
          saltBytes,
          kPbkdf2Iterations,
          kDerivedKeyLength,
        );
        final verifier = formatVerifier(derivedKey, kPbkdf2Iterations);

        // Write directly to fake storage in legacy 3-key format
        await fakeStorage.write(key: 'vault_gesture_verifier', value: verifier);
        await fakeStorage.write(key: 'vault_gesture_salt', value: saltBase64);
        await fakeStorage.write(key: 'vault_gesture_length', value: '3');
        expect(await fakeStorage.read(key: 'vault_gesture_record'), isNull);

        // Derivation 13 (verifyGesture during migration)
        expect(await store.verifyGesture(gesture), isTrue);

        // Combined record now exists and legacy keys are deleted
        final record = await fakeStorage.read(key: 'vault_gesture_record');
        expect(record, equals('$verifier|$saltBase64|3'));
        expect(await fakeStorage.read(key: 'vault_gesture_verifier'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_salt'), isNull);
        expect(await fakeStorage.read(key: 'vault_gesture_length'), isNull);
      },
    );

    test(
      'M3: malformed record (only two parts) returns false for verifyGesture and hasGesture with zero derivations',
      () async {
        await fakeStorage.write(
          key: 'vault_gesture_record',
          value: 'v3:100000:abc|c2FsdDEyMw==',
        );

        // 0 derivations
        expect(await store.hasGesture(), isFalse);
        expect(await store.verifyGesture([1, 0, 1]), isFalse);
      },
    );
  });
}
