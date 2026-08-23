import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

abstract class KeystoreService {
  Future<void> ensureKey();
  Future<String> wrap(String base64Data);
  Future<String> unwrap(String base64Data);
  Future<void> deleteKey();
}

abstract class BiometricKeystoreService {
  Future<void> ensureBioKey();
  Future<String> bioWrap(String base64Data);
  Future<String> bioUnwrap(String base64Data);
  Future<void> deleteBioKey();
  Future<int> bioAvailable();
}

/// Invokes native PBKDF2-HMAC-SHA256 over MethodChannel('mimic/keystore').
Future<Uint8List> nativePbkdf2(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLength,
) async {
  const channel = MethodChannel('mimic/keystore');
  final result = await channel.invokeMethod<Uint8List>('pbkdf2', {
    'password': password,
    'salt': salt,
    'iterations': iterations,
    'keyLength': keyLength,
  });
  if (result == null) throw Exception('PBKDF2 derivation failed or returned null');
  return result;
}

class AndroidKeystoreService implements KeystoreService, BiometricKeystoreService {
  static const MethodChannel _channel = MethodChannel('mimic/keystore');

  @override
  Future<void> ensureKey() async {
    if (kIsWeb) return;
    await _channel.invokeMethod('ensureKey');
  }

  @override
  Future<String> wrap(String base64Data) async {
    if (kIsWeb) return base64Data;
    final bytes = base64Decode(base64Data);
    try {
      final result = await _channel.invokeMethod<Uint8List>('wrap', {'bytes': bytes});
      if (result == null) throw KeystoreWrapException();
      return base64Encode(result);
    } on PlatformException catch (e) {
      throw KeystoreWrapException(e.message ?? 'Keystore wrap failed');
    }
  }

  @override
  Future<String> unwrap(String base64Data) async {
    if (kIsWeb) return base64Data;
    final bytes = base64Decode(base64Data);
    try {
      final result = await _channel.invokeMethod<Uint8List>('unwrap', {'bytes': bytes});
      if (result == null) throw Exception('Keystore unwrap failed');
      return base64Encode(result);
    } on PlatformException catch (e) {
      if (e.code == 'KEY_INVALID') {
        return 'KEY_INVALID';
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteKey() async {
    if (kIsWeb) return;
    await _channel.invokeMethod('deleteKey');
  }

  @override
  Future<void> ensureBioKey() async {
    if (kIsWeb) {
      throw const BiometricUnavailableException(
        code: 'WEB_UNSUPPORTED',
        message: 'Biometrics are not supported on web',
      );
    }
    try {
      await _channel.invokeMethod('ensureBioKey');
    } on PlatformException catch (e) {
      throw _mapBioPlatformException(e);
    }
  }

  @override
  Future<String> bioWrap(String base64Data) async {
    if (kIsWeb) {
      throw const BiometricUnavailableException(
        code: 'WEB_UNSUPPORTED',
        message: 'Biometrics are not supported on web',
      );
    }
    final bytes = base64Decode(base64Data);
    try {
      final result = await _channel.invokeMethod<Uint8List>('bioWrap', {'bytes': bytes});
      if (result == null) {
        throw const BiometricUnavailableException(
          code: 'NULL_RESULT',
          message: 'bioWrap returned null',
        );
      }
      return base64Encode(result);
    } on PlatformException catch (e) {
      throw _mapBioPlatformException(e);
    }
  }

  @override
  Future<String> bioUnwrap(String base64Data) async {
    if (kIsWeb) {
      throw const BiometricUnavailableException(
        code: 'WEB_UNSUPPORTED',
        message: 'Biometrics are not supported on web',
      );
    }
    final bytes = base64Decode(base64Data);
    try {
      final result = await _channel.invokeMethod<Uint8List>('bioUnwrap', {'bytes': bytes});
      if (result == null) {
        throw const BiometricUnavailableException(
          code: 'NULL_RESULT',
          message: 'bioUnwrap returned null',
        );
      }
      return base64Encode(result);
    } on PlatformException catch (e) {
      throw _mapBioPlatformException(e);
    }
  }

  @override
  Future<void> deleteBioKey() async {
    if (kIsWeb) {
      throw const BiometricUnavailableException(
        code: 'WEB_UNSUPPORTED',
        message: 'Biometrics are not supported on web',
      );
    }
    try {
      await _channel.invokeMethod('deleteBioKey');
    } on PlatformException catch (e) {
      throw _mapBioPlatformException(e);
    }
  }

  @override
  Future<int> bioAvailable() async {
    if (kIsWeb) {
      throw const BiometricUnavailableException(
        code: 'WEB_UNSUPPORTED',
        message: 'Biometrics are not supported on web',
      );
    }
    try {
      final result = await _channel.invokeMethod<int>('bioAvailable');
      if (result == null) {
        throw const BiometricUnavailableException(
          code: 'NULL_RESULT',
          message: 'bioAvailable returned null',
        );
      }
      return result;
    } on PlatformException catch (e) {
      throw _mapBioPlatformException(e);
    }
  }
}

class FakeKeystoreService implements KeystoreService, BiometricKeystoreService {
  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    final original = base64Decode(base64Data);
    final iv = Uint8List(12); // dummy IV
    final combined = Uint8List(iv.length + original.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, original);
    return base64Encode(combined);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final combined = base64Decode(base64Data);
    if (combined.length < 12) return 'KEY_INVALID';
    final original = combined.sublist(12);
    return base64Encode(original);
  }

  @override
  Future<void> deleteKey() async {}

  @override
  Future<void> ensureBioKey() async {
    throw const BiometricUnavailableException(
      code: 'FAKE_UNSUPPORTED',
      message: 'Biometrics are not supported in FakeKeystoreService',
    );
  }

  @override
  Future<String> bioWrap(String base64Data) async {
    throw const BiometricUnavailableException(
      code: 'FAKE_UNSUPPORTED',
      message: 'Biometrics are not supported in FakeKeystoreService',
    );
  }

  @override
  Future<String> bioUnwrap(String base64Data) async {
    throw const BiometricUnavailableException(
      code: 'FAKE_UNSUPPORTED',
      message: 'Biometrics are not supported in FakeKeystoreService',
    );
  }

  @override
  Future<void> deleteBioKey() async {
    throw const BiometricUnavailableException(
      code: 'FAKE_UNSUPPORTED',
      message: 'Biometrics are not supported in FakeKeystoreService',
    );
  }

  @override
  Future<int> bioAvailable() async {
    throw const BiometricUnavailableException(
      code: 'FAKE_UNSUPPORTED',
      message: 'Biometrics are not supported in FakeKeystoreService',
    );
  }
}

class KeystoreInvalidException implements Exception {
  final String message = "Your device's secure key is unavailable. Restore your vault with your recovery phrase.";
  @override
  String toString() => message;
}

class KeystoreWrapException implements Exception {
  final String message;
  KeystoreWrapException([this.message = 'Keystore wrap failed']);
  @override
  String toString() => 'KeystoreWrapException: $message';
}

class BiometricKeyInvalidatedException implements Exception {
  final String message;
  const BiometricKeyInvalidatedException([
    this.message = 'Biometric enrollment changed. Please unlock with your PIN.',
  ]);

  @override
  String toString() => 'BiometricKeyInvalidatedException: $message';
}

class BiometricCancelledException implements Exception {
  final String message;
  const BiometricCancelledException([
    this.message = 'Biometric prompt was cancelled.',
  ]);

  @override
  String toString() => 'BiometricCancelledException: $message';
}

class BiometricUnavailableException implements Exception {
  final String code;
  final String? message;

  const BiometricUnavailableException({
    required this.code,
    this.message,
  });

  @override
  String toString() =>
      'BiometricUnavailableException(code: $code, message: $message)';
}

Exception _mapBioPlatformException(PlatformException e) {
  switch (e.code) {
    case 'BIO_KEY_INVALID':
      return const BiometricKeyInvalidatedException();
    case 'BIO_CANCELLED':
      return const BiometricCancelledException();
    default:
      return BiometricUnavailableException(
        code: e.code,
        message: e.message,
      );
  }
}
