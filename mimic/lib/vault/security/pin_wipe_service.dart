// mimic/lib/vault/security/pin_wipe_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/biometric_unlock_store.dart';

class PinWipeService {
  final PlatformService _platformService;
  final BiometricUnlockStore _biometricUnlockStore;

  PinWipeService(this._platformService, {BiometricUnlockStore? biometricUnlockStore})
      : _biometricUnlockStore = biometricUnlockStore ?? BiometricUnlockStore();

  Future<void> wipePin() async {
    if (kIsWeb) return;
    await _platformService.secureDelete('vault_pin_hash');
    await _platformService.secureDelete('vault_pin_salt');
    await _platformService.secureDelete('vault_salt');
    await _platformService.secureDelete('vault_pin');
    await _platformService.secureDelete('wrong_attempts');
    await _biometricUnlockStore.wipeAll();
    
    // Deleting encrypted files and databases from filesystem
    await _deleteAppDirectoryContents();
    
    await _platformService.secureWrite('vault_wiped', 'true');
  }

  Future<void> _deleteAppDirectoryContents() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDir.path);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      final dbPath = await getDatabasesPath();
      final dbDir = Directory(dbPath);
      if (await dbDir.exists()) {
        await for (final entity in dbDir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<bool> isPinWiped() async {
    if (kIsWeb) return false;
    final setup = await _platformService.secureRead('vault_setup_completed');
    if (setup != 'true') return false;
    final hash = await _platformService.secureRead('vault_pin_hash');
    return hash == null;
  }
}

final pinWipeServiceProvider = Provider<PinWipeService>((ref) {
  return PinWipeService(ref.read(platformServiceProvider));
});
