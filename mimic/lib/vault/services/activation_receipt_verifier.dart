import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Verified claims from a version-1 activation exchange, not a grant of Pro.
/// This isolated verifier performs no network, storage or entitlement writes.
class VerifiedActivationReceipt {
  const VerifiedActivationReceipt({
    required this.keyId,
    required this.licenseType,
    required this.issuedAt,
  });

  final String keyId;
  final int licenseType;
  final DateTime issuedAt;
}

/// RSA-SHA256/PKCS1-v1_5 only. Keys come from trusted application configuration,
/// never from the response. No production keys are installed by this module.
class ActivationReceiptVerifier {
  ActivationReceiptVerifier({
    required Map<String, RSAPublicKey> trustedKeys,
    required this.audience,
    DateTime Function()? clock,
  }) : _keys = Map.unmodifiable(trustedKeys),
       _clock = clock ?? DateTime.now {
    if (audience.isEmpty || audience.length > 128 || _keys.length > 16) {
      throw ArgumentError('Invalid receipt verifier configuration');
    }
    for (final entry in _keys.entries) {
      final key = entry.value;
      if (!_keyIdPattern.hasMatch(entry.key) ||
          key.modulus == null ||
          key.modulus!.bitLength < 2048 ||
          key.modulus!.bitLength > 4096 ||
          !key.modulus!.isOdd ||
          key.exponent != BigInt.from(65537)) {
        throw ArgumentError('Invalid pinned receipt key');
      }
    }
  }

  final Map<String, RSAPublicKey> _keys;
  final String audience;
  final DateTime Function() _clock;
  static final _keyIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
  static final _encodedPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _noncePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final _codePattern = RegExp(
    r'^MIMIC-(01|02)[0-9A-F]{2}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$',
  );

  /// Verify a fresh exchange against its locally retained request values.
  /// The nonce must be a fresh 32-byte cryptographically random base64url value.
  /// This is NOT a persisted-receipt replay validator: lifetime offline access
  /// and request nonce consumption belong to the later activation integration.
  VerifiedActivationReceipt? verify(
    Map<String, dynamic> envelope, {
    required String licenseCode,
    required String deviceId,
    required String requestNonce,
  }) {
    try {
      if (!_codePattern.hasMatch(licenseCode) ||
          deviceId.isEmpty ||
          deviceId.length > 128 ||
          !_noncePattern.hasMatch(requestNonce) ||
          _decode(requestNonce, 32)?.length != 32 ||
          !_hasFields(envelope, const {'kid', 'payload', 'signature'})) {
        return null;
      }
      final keyId = envelope['kid'];
      if (keyId is! String || !_keyIdPattern.hasMatch(keyId)) return null;
      final key = _keys[keyId];
      if (key == null) return null;
      final payload = _decode(envelope['payload'], 2048);
      final signature = _decode(envelope['signature'], 512);
      if (payload == null ||
          signature == null ||
          signature.length != (key.modulus!.bitLength + 7) ~/ 8) {
        return null;
      }
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(key));
      if (!verifier.verifySignature(payload, RSASignature(signature))) {
        return null;
      }

      // Decode only after authenticating the exact bytes, not reserialized JSON.
      final claims = jsonDecode(utf8.decode(payload));
      if (claims is! Map<String, dynamic> ||
          !_hasFields(claims, const {
            'v',
            'kid',
            'aud',
            'licenseHash',
            'deviceId',
            'nonce',
            'type',
            'issuedAt',
          }) ||
          claims['v'] is! int ||
          claims['v'] != 1 ||
          claims['kid'] != keyId ||
          claims['aud'] != audience ||
          claims['licenseHash'] !=
              sha256.convert(utf8.encode(licenseCode)).toString() ||
          claims['deviceId'] != deviceId ||
          claims['nonce'] != requestNonce ||
          claims['type'] is! int ||
          !const {1, 2}.contains(claims['type']) ||
          claims['type'] != int.parse(licenseCode.substring(6, 8), radix: 16)) {
        return null;
      }
      final issuedAt = claims['issuedAt'];
      // Unix seconds, bounded independently of DateTime's platform limits.
      // No expiry: these receipts represent lifetime access.
      if (issuedAt is! int ||
          issuedAt <= 0 ||
          issuedAt > 253402300799 ||
          issuedAt > _clock().toUtc().millisecondsSinceEpoch ~/ 1000 + 300) {
        return null;
      }
      return VerifiedActivationReceipt(
        keyId: keyId,
        licenseType: claims['type'] as int,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(
          issuedAt * 1000,
          isUtc: true,
        ),
      );
    } catch (_) {
      // Malformed/untrusted input or crypto parsing errors must fail closed.
      return null;
    }
  }

  static bool _hasFields(Map<String, dynamic> value, Set<String> fields) =>
      value.length == fields.length && value.keys.every(fields.contains);

  static Uint8List? _decode(dynamic value, int maxBytes) {
    if (value is! String ||
        value.isEmpty ||
        value.length > (maxBytes * 4 + 2) ~/ 3 ||
        !_encodedPattern.hasMatch(value)) {
      return null;
    }
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length > maxBytes ||
        base64Url.encode(bytes).replaceAll('=', '') != value) {
      return null;
    }
    return bytes;
  }
}
