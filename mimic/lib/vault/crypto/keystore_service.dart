import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

abstract class KeystoreService {
  Future<void> ensureKey();
  Future<String> wrap(String base64Data);
  Future<String> unwrap(String base64Data);
  Future<void> deleteKey();
}

class AndroidKeystoreService implements KeystoreService {
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
}

class FakeKeystoreService implements KeystoreService {
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
