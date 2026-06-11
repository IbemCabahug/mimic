// lib/core/services/platform_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

abstract class PlatformService {
  Future<String?> secureRead(String key);
  Future<void> secureWrite(String key, String value);
  Future<void> secureDelete(String key);
  Future<void> saveEncryptedFile(String path, Uint8List data);
  Future<Uint8List?> readEncryptedFile(String path);
  Future<void> deleteFile(String path);
  bool isWeb();
}

class AndroidPlatformService implements PlatformService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String> _resolveVaultFilePath(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'vault_files'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return p.join(dir.path, name);
  }

  @override
  bool isWeb() => false;

  @override
  Future<void> secureWrite(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  @override
  Future<String?> secureRead(String key) async {
    return await _secureStorage.read(key: key);
  }

  @override
  Future<void> secureDelete(String key) async {
    await _secureStorage.delete(key: key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    final resolved = await _resolveVaultFilePath(path);
    final file = File(resolved);
    await file.writeAsBytes(data);
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async {
    final resolved = await _resolveVaultFilePath(path);
    final file = File(resolved);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> deleteFile(String path) async {
    final resolved = await _resolveVaultFilePath(path);
    final file = File(resolved);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class WebPlatformService implements PlatformService {
  SharedPreferences? _prefs;

  @override
  bool isWeb() => true;

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<void> secureWrite(String key, String value) async {
    await _ensureInitialized();
    await _prefs!.setString(key, value);
  }

  @override
  Future<String?> secureRead(String key) async {
    await _ensureInitialized();
    return _prefs!.getString(key);
  }

  @override
  Future<void> secureDelete(String key) async {
    await _ensureInitialized();
    await _prefs!.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    await _ensureInitialized();
    await _prefs!.setString('enc_$path', base64Encode(data));
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async {
    await _ensureInitialized();
    final encoded = _prefs!.getString('enc_$path');
    if (encoded != null) {
      return base64Decode(encoded);
    }
    return null;
  }

  @override
  Future<void> deleteFile(String path) async {
    await _ensureInitialized();
    await _prefs!.remove('enc_$path');
  }
}

final platformServiceProvider = Provider<PlatformService>((ref) {
  if (kIsWeb) {
    return WebPlatformService();
  } else {
    return AndroidPlatformService();
  }
});
