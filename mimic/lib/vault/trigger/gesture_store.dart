// lib/vault/trigger/gesture_store.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/vault_kdf.dart';

/// Manages persistence and verification of user-chosen unlock gestures.
///
/// HONEST SECURITY LIMIT & ZONE CONSTRAINTS:
/// The gesture sequence is strictly constrained by in-game voting mechanics:
/// - A tap is recorded when a vote is submitted on the voting screen.
/// - The game enforces a 3-player minimum, meaning a 3-player round provides
///   exactly 3 vote submissions and player candidate indices 0, 1, and 2.
/// - A sequence longer than 3 taps or containing an index > 2 could never be
///   physically entered in a 3-player match.
///
/// This yields a maximum of 24 usable combinations (3^3 = 27 total, minus the 3
/// all-identical sequences [0,0,0], [1,1,1], and [2,2,2]).
///
/// Anyone with access to the device's secure storage can enumerate and test all
/// 24 possibilities in seconds, regardless of PBKDF2 iterations.
///
/// The unlock gesture is therefore OBSCURITY, not a second password. Its value
/// is that the unlock sequence is no longer hardcoded into source code, cannot
/// be published in documentation or repositories, and differs on each
/// installation.
///
/// Constant-time comparison is defence in depth against timing attacks during
/// live interaction, not the primary barrier protecting the secret. The gesture
/// is NOT brute-force-resistant, cryptographically strong, or equivalent to
/// the vault PIN.
class GestureStore {
  GestureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String _verifierKey = 'vault_gesture_verifier';
  static const String _saltKey = 'vault_gesture_salt';
  static const String _lengthKey = 'vault_gesture_length';

  /// Required gesture length in taps (exactly 3).
  static const int requiredGestureLength = 3;

  /// Maximum allowed zone index (0, 1, or 2).
  static const int maxZoneIndex = 2;

  void _validateGesture(List<int> gesture) {
    if (gesture.length != requiredGestureLength) {
      throw ArgumentError(
        'Gesture length must be exactly $requiredGestureLength taps, got ${gesture.length}',
      );
    }
    if (gesture.any((element) => element < 0)) {
      final negative = gesture.firstWhere((element) => element < 0);
      throw ArgumentError('Gesture elements must be non-negative (>= 0), got $negative');
    }
    if (gesture.any((element) => element > maxZoneIndex)) {
      final excessive = gesture.firstWhere((element) => element > maxZoneIndex);
      throw ArgumentError('Gesture elements must not exceed $maxZoneIndex, got $excessive');
    }
    if (gesture.every((element) => element == gesture.first)) {
      throw ArgumentError('Gesture elements cannot all be identical (got all ${gesture.first})');
    }
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// Sets a new unlock gesture, deriving a salted v3 verifier and persisting it.
  ///
  /// Throws [ArgumentError] if the gesture fails validation.
  Future<void> setGesture(List<int> gesture) async {
    _validateGesture(gesture);

    final saltBase64 = _generateSalt();

    // The comma separator is mandatory: without it [1, 23] and [12, 3] would
    // both serialize to "123" and would erroneously unlock each other.
    final canonical = gesture.join(',');
    final passwordBytes = Uint8List.fromList(utf8.encode(canonical));
    final saltBytes = base64Decode(saltBase64);

    final derivedKey = await derivePbkdf2Async(
      passwordBytes,
      saltBytes,
      kPbkdf2Iterations,
      kDerivedKeyLength,
    );

    final verifier = formatVerifier(derivedKey, kPbkdf2Iterations);

    await _storage.write(key: _verifierKey, value: verifier);
    await _storage.write(key: _saltKey, value: saltBase64);
    // Storing the gesture length in plaintext is safe: an attacker who can read
    // secure storage can already brute-force the tiny gesture space in seconds,
    // so knowing the length reveals nothing new. Storing it keeps the detector to
    // one verification per tap. With a fixed 3-tap gesture the length is now
    // effectively constant; the key is retained so a future variable-length
    // gesture needs no storage migration.
    await _storage.write(key: _lengthKey, value: gesture.length.toString());
  }

  /// Verifies a candidate gesture against the stored verifier using constant-time comparison.
  ///
  /// Returns false if no gesture is currently stored or if verification fails.
  Future<bool> verifyGesture(List<int> gesture) async {
    final storedVerifier = await _storage.read(key: _verifierKey);
    final storedSalt = await _storage.read(key: _saltKey);
    final storedLength = await _storage.read(key: _lengthKey);

    // The length is checked so verifyGesture and hasGesture agree on incomplete state.
    if (storedVerifier == null || storedSalt == null || storedLength == null) {
      return false;
    }

    final canonical = gesture.join(',');
    final passwordBytes = Uint8List.fromList(utf8.encode(canonical));
    final saltBytes = base64Decode(storedSalt);

    final derivedKey = await derivePbkdf2Async(
      passwordBytes,
      saltBytes,
      kPbkdf2Iterations,
      kDerivedKeyLength,
    );

    final expectedVerifier = formatVerifier(derivedKey, kPbkdf2Iterations);
    return constantTimeEquals(storedVerifier, expectedVerifier);
  }

  /// Returns the stored gesture length, or null if unconfigured or unparseable.
  Future<int?> gestureLength() async {
    try {
      final raw = await _storage.read(key: _lengthKey);
      if (raw == null) return null;
      return int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if all three gesture records (verifier, salt, and length) are stored.
  Future<bool> hasGesture() async {
    final verifier = await _storage.read(key: _verifierKey);
    final salt = await _storage.read(key: _saltKey);
    final length = await _storage.read(key: _lengthKey);
    return verifier != null && salt != null && length != null;
  }

  /// Removes the stored gesture verifier, salt, and length.
  Future<void> clearGesture() async {
    await _storage.delete(key: _verifierKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _lengthKey);
  }
}
