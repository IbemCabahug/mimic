// lib/vault/services/license_service.dart
//
// Offline cryptographic license key service for Mimic Pro with optional
// 1-time device registration to prevent sharing between friends.
//
// Enables redemption and verification of lifetime Pro licenses for direct
// GitHub Releases, GCash/PayMongo, and third-party distribution.
//
// Key format: MIMIC-XXXX-XXXX-XXXX-XXXX (16 hexadecimal characters formatted into 4 groups)
// - Byte 0: License type (0x01 = Lifetime Pro, 0x02 = Beta Tester)
// - Bytes 1-3: Unique nonce / issue entropy (24-bit random, >16.7M unique codes)
// - Bytes 4-7: 32-bit HMAC-SHA256 signature tag computed with secret salt
//
// Anti-Piracy Architecture:
// 1. Initial Activation: If an activation server URL is configured (e.g. Google Apps Script),
//    the app registers its anonymous unique Device ID on first redemption (max 2 devices).
//    Once registered, the app is 100% unlocked offline forever.
// 2. Offline Resilience: If no activation server is configured or in debug/offline mode,
//    local mathematical HMAC verification runs immediately.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/platform_service.dart';
import 'pro_status_service.dart';

/// Supported offline license types.
enum LicenseType {
  lifetimePro(0x01, 'Lifetime Pro'),
  betaTester(0x02, 'Beta Tester Access'),
  unknown(0x00, 'Unknown');

  const LicenseType(this.code, this.displayName);
  final int code;
  final String displayName;

  static LicenseType fromCode(int code) {
    for (final type in LicenseType.values) {
      if (type.code == code) return type;
    }
    return LicenseType.unknown;
  }
}

/// Result of license key validation or redemption.
class LicenseValidationResult {
  const LicenseValidationResult({
    required this.isValid,
    this.type = LicenseType.unknown,
    this.errorMessage,
    this.formattedKey,
  });

  final bool isValid;
  final LicenseType type;
  final String? errorMessage;
  final String? formattedKey;

  bool get isSuccess => isValid && errorMessage == null;

  static const LicenseValidationResult invalidFormat = LicenseValidationResult(
    isValid: false,
    errorMessage: 'Invalid license key format. Please enter a valid 16-character code.',
  );

  static const LicenseValidationResult signatureMismatch = LicenseValidationResult(
    isValid: false,
    errorMessage: 'Invalid or unrecognized activation code. Please double-check and try again.',
  );

  static const LicenseValidationResult unsupportedType = LicenseValidationResult(
    isValid: false,
    errorMessage: 'Unsupported license type.',
  );

  static const LicenseValidationResult deviceLimitReached = LicenseValidationResult(
    isValid: false,
    errorMessage: 'This activation code has already reached its maximum device limit (2 devices).',
  );

  static const LicenseValidationResult networkRequired = LicenseValidationResult(
    isValid: false,
    errorMessage: 'Internet connection is required once to activate this device. Please connect to Wi-Fi or mobile data.',
  );
}

/// Information about an active redeemed license.
class LicenseInfo {
  const LicenseInfo({
    required this.formattedKey,
    required this.type,
    required this.redeemedAt,
    this.deviceId,
  });

  final String formattedKey;
  final LicenseType type;
  final DateTime redeemedAt;
  final String? deviceId;
}

/// Default offline signing secret key.
/// Can be overridden at build time using `--dart-define=MIMIC_LICENSE_SECRET=...`.
const String kDefaultLicenseSecret =
    'mimic_offline_pro_license_secret_2026_gc_v1';

const String kCompileTimeLicenseSecret = String.fromEnvironment(
  'MIMIC_LICENSE_SECRET',
  defaultValue: kDefaultLicenseSecret,
);

/// Optional Google Apps Script or cloud activation endpoint URL.
/// Can be passed at build time via `--dart-define=MIMIC_ACTIVATION_URL=...`.
const String kCompileTimeActivationUrl = String.fromEnvironment(
  'MIMIC_ACTIVATION_URL',
  defaultValue: '',
);

/// Secure storage keys for offline license persistence.
const String kStoredLicenseKey = 'pro_offline_license_key';
const String kStoredLicenseRedeemedAt = 'pro_offline_license_redeemed_at';
const String kStoredLicenseTypeCode = 'pro_offline_license_type_code';
const String kStoredLicenseDeviceId = 'pro_offline_device_id';

class LicenseService {
  LicenseService({
    required PlatformService platform,
    required ProStatusService proStatus,
    String? secretKey,
    String? activationUrl,
    Future<Map<String, dynamic>> Function(String url, Map<String, dynamic> body)? httpPoster,
  })  : _platform = platform,
        _proStatus = proStatus,
        _secretKey = (secretKey ?? kCompileTimeLicenseSecret).trim(),
        _activationUrl = (activationUrl ?? kCompileTimeActivationUrl).trim(),
        _httpPoster = httpPoster;

  final PlatformService _platform;
  final ProStatusService _proStatus;
  final String _secretKey;
  final String _activationUrl;
  final Future<Map<String, dynamic>> Function(String url, Map<String, dynamic> body)? _httpPoster;

  /// Retrieves or generates a persistent Device ID for this install.
  /// On Android, utilizes Settings.Secure.ANDROID_ID which survives app
  /// uninstallation and reinstallation, ensuring paying customers can restore
  /// purchases on the same device without consuming extra device slots.
  Future<String> getOrCreateDeviceId() async {
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('mimic/device');
        final hwId = await channel.invokeMethod<String>('getDeviceId');
        if (hwId != null && hwId.trim().isNotEmpty) {
          return 'android-${hwId.trim()}';
        }
      }
    } catch (_) {}

    try {
      var id = await _platform.secureRead(kStoredLicenseDeviceId);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await _platform.secureWrite(kStoredLicenseDeviceId, id);
      }
      return id;
    } catch (_) {
      return const Uuid().v4();
    }
  }

  /// Normalizes and formats raw user input into standard MIMIC-XXXX-XXXX-XXXX-XXXX.
  static String? sanitizeAndFormatKey(String rawInput) {
    var cleaned = rawInput.trim().toUpperCase();
    if (cleaned.startsWith('MIMIC-')) {
      cleaned = cleaned.substring(6);
    } else if (cleaned.startsWith('MIMIC')) {
      cleaned = cleaned.substring(5);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9A-F]'), '');

    if (cleaned.length != 16) return null;

    return 'MIMIC-${cleaned.substring(0, 4)}-${cleaned.substring(4, 8)}-${cleaned.substring(8, 12)}-${cleaned.substring(12, 16)}';
  }

  /// Extracts the 16 hex characters from any formatted or raw key.
  static String? extractHex16(String rawInput) {
    var cleaned = rawInput.trim().toUpperCase();
    if (cleaned.startsWith('MIMIC-')) {
      cleaned = cleaned.substring(6);
    } else if (cleaned.startsWith('MIMIC')) {
      cleaned = cleaned.substring(5);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9A-F]'), '');
    return cleaned.length == 16 ? cleaned : null;
  }

  /// Generates a valid offline license key.
  String generateKey({
    LicenseType type = LicenseType.lifetimePro,
    String? customNonce,
  }) {
    final typeByte = type.code;

    List<int> nonceBytes;
    if (customNonce != null && customNonce.length == 6) {
      nonceBytes = [
        int.parse(customNonce.substring(0, 2), radix: 16),
        int.parse(customNonce.substring(2, 4), radix: 16),
        int.parse(customNonce.substring(4, 6), radix: 16),
      ];
    } else {
      final rng = Random.secure();
      nonceBytes = [rng.nextInt(256), rng.nextInt(256), rng.nextInt(256)];
    }

    final payloadBytes = [typeByte, ...nonceBytes];
    final tagBytes = _computeTag(payloadBytes);

    final allBytes = [...payloadBytes, ...tagBytes];
    final hexString = allBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

    return 'MIMIC-${hexString.substring(0, 4)}-${hexString.substring(4, 8)}-${hexString.substring(8, 12)}-${hexString.substring(12, 16)}';
  }

  /// Validates a license key offline using HMAC-SHA256 signature verification.
  LicenseValidationResult validateKey(String rawInput) {
    final hex16 = extractHex16(rawInput);
    if (hex16 == null) {
      return LicenseValidationResult.invalidFormat;
    }

    final bytes = <int>[];
    for (var i = 0; i < 16; i += 2) {
      bytes.add(int.parse(hex16.substring(i, i + 2), radix: 16));
    }

    final payloadBytes = bytes.sublist(0, 4);
    final providedTag = bytes.sublist(4, 8);

    final expectedTag = _computeTag(payloadBytes);

    var diff = 0;
    for (var i = 0; i < 4; i++) {
      diff |= providedTag[i] ^ expectedTag[i];
    }

    if (diff != 0) {
      return LicenseValidationResult.signatureMismatch;
    }

    final type = LicenseType.fromCode(payloadBytes[0]);
    if (type == LicenseType.unknown) {
      return LicenseValidationResult.unsupportedType;
    }

    final formatted = 'MIMIC-${hex16.substring(0, 4)}-${hex16.substring(4, 8)}-${hex16.substring(8, 12)}-${hex16.substring(12, 16)}';

    return LicenseValidationResult(
      isValid: true,
      type: type,
      formattedKey: formatted,
    );
  }

  /// Validates and redeems a license key.
  ///
  /// If an activation server is configured, performs a 1-time device registration
  /// check to enforce the 2-device limit. Once redeemed, Pro is unlocked permanently offline.
  Future<LicenseValidationResult> redeemKey(String rawInput) async {
    // 1. First verify cryptographic validity locally
    final validation = validateKey(rawInput);
    if (!validation.isSuccess) {
      return validation;
    }

    final formattedKey = validation.formattedKey!;
    final deviceId = await getOrCreateDeviceId();

    // 2. If activation server URL is set, enforce device limit check
    if (_activationUrl.isNotEmpty) {
      try {
        final Map<String, dynamic> responseData;
        if (_httpPoster != null) {
          responseData = await _httpPoster(_activationUrl, {
            'action': 'activate',
            'key': formattedKey,
            'deviceId': deviceId,
          });
        } else {
          responseData = await _defaultHttpPost(_activationUrl, {
            'action': 'activate',
            'key': formattedKey,
            'deviceId': deviceId,
          });
        }

        final success = responseData['success'] == true;
        if (!success) {
          final error = responseData['error']?.toString();
          if (error == 'DEVICE_LIMIT_REACHED') {
            return LicenseValidationResult.deviceLimitReached;
          }
          final msg = responseData['message']?.toString() ??
              'Activation was not authorized. Please check your key.';
          return LicenseValidationResult(isValid: false, errorMessage: msg);
        }
      } catch (_) {
        return LicenseValidationResult.networkRequired;
      }
    }

    // 3. Grant Pro status and persist license locally
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _proStatus.grantPro();
      await _platform.secureWrite(kStoredLicenseKey, formattedKey);
      await _platform.secureWrite(kStoredLicenseRedeemedAt, nowIso);
      await _platform.secureWrite(
        kStoredLicenseTypeCode,
        validation.type.code.toString(),
      );
      await _platform.secureWrite(kStoredLicenseDeviceId, deviceId);

      return validation;
    } catch (_) {
      return const LicenseValidationResult(
        isValid: false,
        errorMessage: 'Failed to securely store license. Please try again.',
      );
    }
  }

  /// Retrieves the currently redeemed license info if available.
  Future<LicenseInfo?> getRedeemedLicense() async {
    try {
      final key = await _platform.secureRead(kStoredLicenseKey);
      if (key == null || key.isEmpty) return null;

      final redeemedAtStr = await _platform.secureRead(kStoredLicenseRedeemedAt);
      final typeCodeStr = await _platform.secureRead(kStoredLicenseTypeCode);
      final deviceId = await _platform.secureRead(kStoredLicenseDeviceId);

      final typeCode = int.tryParse(typeCodeStr ?? '1') ?? 1;
      final type = LicenseType.fromCode(typeCode);
      final redeemedAt = redeemedAtStr != null
          ? (DateTime.tryParse(redeemedAtStr) ?? DateTime.now())
          : DateTime.now();

      return LicenseInfo(
        formattedKey: key,
        type: type,
        redeemedAt: redeemedAt,
        deviceId: deviceId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Computes a 4-byte (32-bit) HMAC-SHA256 signature tag over the payload.
  List<int> _computeTag(List<int> payload) {
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final digest = hmac.convert(payload);
    return digest.bytes.sublist(0, 4);
  }

  /// Built-in HTTP client for Android and iOS without third-party dependencies.
  static Future<Map<String, dynamic>> _defaultHttpPost(
    String url,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(url);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      return jsonDecode(responseText) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}

/// Riverpod provider for [LicenseService].
final licenseServiceProvider = Provider<LicenseService>((ref) {
  final platform = ref.read(platformServiceProvider);
  final proStatus = ref.read(proStatusServiceProvider);
  return LicenseService(platform: platform, proStatus: proStatus);
});
