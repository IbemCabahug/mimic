// lib/vault/services/billing_verifier.dart
//
// Cryptographic verification of Google Play in-app purchase receipts.
//
// Background:
// Google Play signs the purchase JSON ('localVerificationData') with its
// private key using SHA256withRSA (or SHA1withRSA for legacy devices).
// The resulting signature is base64-encoded in 'serverVerificationData'.
//
// This verifier parses the developer's Base64-encoded RSA public key
// (X.509 SubjectPublicKeyInfo) and verifies the digital signature locally
// without needing an external verification backend.

import 'dart:convert';
import 'dart:typed_data';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'billing_service.dart' show kProProductId;

/// Contract for verifying purchase receipts before granting entitlements.
abstract interface class PurchaseVerifier {
  /// Returns `true` if [purchase] is cryptographically authentic and valid.
  bool verify(PurchaseDetails purchase);
}

/// Permissive verifier used exclusively in unit tests or local development fixtures.
class DevelopmentPurchaseVerifier implements PurchaseVerifier {
  const DevelopmentPurchaseVerifier({this.allowAll = true});

  final bool allowAll;

  @override
  bool verify(PurchaseDetails purchase) {
    if (!allowAll) return false;
    return purchase.verificationData.localVerificationData.isNotEmpty;
  }
}

/// Cryptographically validates Google Play in-app purchase receipts
/// using PointyCastle RSA signature verification.
class GooglePlaySignatureVerifier implements PurchaseVerifier {
  GooglePlaySignatureVerifier({
    this.base64PublicKey,
    this.expectedProductId = kProProductId,
    this.expectedPackageName,
    this.allowUnverifiedWhenNoKey = false,
  }) {
    if (base64PublicKey != null && base64PublicKey!.trim().isNotEmpty) {
      _cachedKey = _parseSpkiPublicKey(base64PublicKey!.trim());
    }
  }

  /// Base64-encoded RSA public key from the Google Play Console
  /// (Monetization setup -> Licensing).
  final String? base64PublicKey;

  /// Expected product identifier (defaults to `kProProductId`).
  final String expectedProductId;

  /// Optional expected package name (e.g. `com.example.mimic` or `com.ibem.mimic`).
  final String? expectedPackageName;

  /// Whether to allow purchases when no public key has been configured.
  /// Should be false in production release builds.
  final bool allowUnverifiedWhenNoKey;

  RSAPublicKey? _cachedKey;

  @override
  bool verify(PurchaseDetails purchase) {
    final verificationData = purchase.verificationData;

    // 1. Basic structural presence check
    final localData = verificationData.localVerificationData;
    if (localData.isEmpty) return false;

    // 2. Validate purchase payload format and content
    try {
      final decoded = json.decode(localData);
      if (decoded is! Map<String, dynamic>) return false;

      // Product ID inside receipt must match expected product
      final productId = decoded['productId'] as String?;
      if (productId != expectedProductId) return false;

      // Package name check if configured
      if (expectedPackageName != null) {
        final pkg = decoded['packageName'] as String?;
        if (pkg != expectedPackageName) return false;
      }
    } catch (_) {
      // Malformed JSON is rejected
      return false;
    }

    // 3. Digital signature verification
    final pubKey = _cachedKey;
    if (pubKey == null) {
      // If no public key is configured, check if explicit dev fallback is permitted
      return allowUnverifiedWhenNoKey;
    }

    final signatureStr = verificationData.serverVerificationData;
    if (signatureStr.isEmpty) return false;

    try {
      final signatureBytes = base64.decode(signatureStr);
      final dataBytes = Uint8List.fromList(utf8.encode(localData));

      return _verifyRsaSignature(dataBytes, signatureBytes, pubKey);
    } catch (_) {
      return false;
    }
  }

  /// Verifies [signatureBytes] against [dataBytes] using [pubKey].
  /// Tries SHA-256 with RSA first (modern Google Play standard),
  /// falling back to SHA-1 with RSA (older Google Play signatures).
  static bool _verifyRsaSignature(
    Uint8List dataBytes,
    Uint8List signatureBytes,
    RSAPublicKey pubKey,
  ) {
    // 1. Try SHA-256 / RSA
    try {
      final signer = RSASigner(SHA256Digest(), '06092a864886f70d01010b');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(pubKey));
      final verified =
          signer.verifySignature(dataBytes, RSASignature(signatureBytes));
      if (verified) return true;
    } catch (_) {}

    // 2. Try SHA-1 / RSA fallback
    try {
      final signer = RSASigner(SHA1Digest(), '06092a864886f70d010105');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(pubKey));
      final verified =
          signer.verifySignature(dataBytes, RSASignature(signatureBytes));
      if (verified) return true;
    } catch (_) {}

    return false;
  }

  /// Parses a Base64-encoded X.509 SubjectPublicKeyInfo into an [RSAPublicKey].
  static RSAPublicKey _parseSpkiPublicKey(String base64Key) {
    final derBytes = base64.decode(base64Key.replaceAll(RegExp(r'\s+'), ''));
    final parser = ASN1Parser(derBytes);
    final spkiSeq = parser.nextObject() as ASN1Sequence;

    // spkiSeq[0] = AlgorithmIdentifier, spkiSeq[1] = BIT STRING
    final bitString = spkiSeq.elements![1] as ASN1BitString;
    final pkcs1Bytes = bitString.stringValues as Uint8List;

    // Inside the bit string is the PKCS#1 RSAPublicKey:
    // SEQUENCE { INTEGER (modulus), INTEGER (publicExponent) }
    final pkcs1Parser = ASN1Parser(pkcs1Bytes);
    final pkcs1Seq = pkcs1Parser.nextObject() as ASN1Sequence;

    final modulus = (pkcs1Seq.elements![0] as ASN1Integer).integer!;
    final exponent = (pkcs1Seq.elements![1] as ASN1Integer).integer!;

    return RSAPublicKey(modulus, exponent);
  }
}
