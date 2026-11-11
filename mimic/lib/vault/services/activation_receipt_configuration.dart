import 'dart:convert';

import 'package:pointycastle/export.dart';

import 'activation_receipt_verifier.dart';

/// Staging-only opt-in. Public values only: never supply a private PEM here.
class ActivationReceiptConfiguration {
  const ActivationReceiptConfiguration({
    required this.enabled,
    required this.staging,
    required this.keyId,
    required this.publicModulus,
  });

  const ActivationReceiptConfiguration.fromEnvironment()
    : enabled = const bool.fromEnvironment('MIMIC_SIGNED_ACTIVATION'),
      staging = const bool.fromEnvironment('MIMIC_STAGING'),
      keyId = const String.fromEnvironment('MIMIC_RECEIPT_KEY_ID'),
      publicModulus = const String.fromEnvironment(
        'MIMIC_RECEIPT_PUBLIC_MODULUS',
      );

  final bool enabled;
  final bool staging;
  final String keyId;

  /// Canonical unpadded base64url RSA modulus (JWK `n`); exponent fixed at 65537.
  final String publicModulus;

  /// Invalid/missing config returns no verifier. Callers must retain [enabled]
  /// independently, so invalid opt-in cannot fall back to legacy activation.
  ActivationReceiptVerifier? createVerifier() {
    if (!enabled || !staging) return null;
    try {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(keyId) ||
          publicModulus.length > 683 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(publicModulus)) {
        return null;
      }
      final bytes = base64Url.decode(base64Url.normalize(publicModulus));
      if (!const {256, 384, 512}.contains(bytes.length) ||
          bytes.first < 128 ||
          base64Url.encode(bytes).replaceAll('=', '') != publicModulus) {
        return null;
      }
      final modulus = BigInt.parse(
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      );
      return ActivationReceiptVerifier(
        trustedKeys: {keyId: RSAPublicKey(modulus, BigInt.from(65537))},
        audience: 'com.ibem.mimic.staging:activation',
      );
    } catch (_) {
      return null;
    }
  }
}
