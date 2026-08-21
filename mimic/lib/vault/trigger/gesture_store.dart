// lib/vault/trigger/gesture_store.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/vault_kdf.dart';

/// Manages persistence and verification of user-chosen unlock gestures.
///
/// HONEST SECURITY LIMIT:
/// The gesture space is small — a handful of zones and a few taps yields at
/// most a few thousand combinations. Anyone with access to the device's secure
/// storage can enumerate and test all possibilities in seconds, regardless of
/// hashing or PBKDF2 iterations.
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

  /// Minimum allowable gesture length (taps/zones).
  static const int minGestureLength = 4;

  /// Maximum allowable gesture length (taps/zones).
  static const int maxGestureLength = 8;

  void _validateGesture(List<int> gesture) {
    if (gesture.length < minGestureLength || gesture.length > maxGestureLength) {
      throw ArgumentError(
        'Gesture length must be between $minGestureLength and $maxGestureLength inclusive, got ${gesture.length}',
      );
    }
    if (gesture.any((element) => element < 0)) {
      throw ArgumentError('Gesture elements must be non-negative (>= 0)');
    }
    if (gesture.every((element) => element == gesture.first)) {
      throw ArgumentError('Gesture elements cannot all be identical');
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
  }

  /// Verifies a candidate gesture against the stored verifier using constant-time comparison.
  ///
  /// Returns false if no gesture is currently stored or if verification fails.
  Future<bool> verifyGesture(List<int> gesture) async {
    final storedVerifier = await _storage.read(key: _verifierKey);
    final storedSalt = await _storage.read(key: _saltKey);

    if (storedVerifier == null || storedSalt == null) {
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

  /// Returns true if a gesture verifier and salt are stored.
  Future<bool> hasGesture() async {
    final verifier = await _storage.read(key: _verifierKey);
    final salt = await _storage.read(key: _saltKey);
    return verifier != null && salt != null;
  }

  /// Removes the stored gesture verifier and salt.
  Future<void> clearGesture() async {
    await _storage.delete(key: _verifierKey);
    await _storage.delete(key: _saltKey);
  }
}
