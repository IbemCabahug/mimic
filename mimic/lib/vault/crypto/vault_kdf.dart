// lib/vault/crypto/vault_kdf.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// Private immutable constants for KDF parameters
const int _pbkdf2Iterations = 100000;
const int _derivedKeyLength = 32;

/// Derives a PIN-based key-encryption key (KEK) from a PIN and base64-encoded salt.
///
/// This function reproduces the exact algorithm previously implemented in
/// `VaultCrypto._deriveKey`. It is synchronous and pure.
Uint8List deriveVaultPinKek(String pin, String saltBase64) {
  final salt = base64Decode(saltBase64);
  final pinBytes = Uint8List.fromList(utf8.encode(pin));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _derivedKeyLength));
  return pbkdf2.process(pinBytes);
}
