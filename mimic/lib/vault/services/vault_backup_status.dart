// lib/vault/services/vault_backup_status.dart
import 'package:shared_preferences/shared_preferences.dart';

class VaultBackupStatus {
  static const _keyAt = 'vault_last_export_at';
  static const _keyCount = 'vault_last_export_count';
  static const _keyFilename = 'vault_last_export_filename';

  final SharedPreferences _prefs;
  VaultBackupStatus(this._prefs);

  static Future<VaultBackupStatus> init() async {
    return VaultBackupStatus(await SharedPreferences.getInstance());
  }

  Future<void> recordExport(int count, String filename) async {
    await _prefs.setString(_keyAt, DateTime.now().toIso8601String());
    await _prefs.setInt(_keyCount, count);
    await _prefs.setString(_keyFilename, filename);
  }

  bool isBackupOutOfDate(int currentTotalCount) {
    if (!_prefs.containsKey(_keyCount)) return true;
    final lastCount = _prefs.getInt(_keyCount);
    return lastCount != currentTotalCount;
  }

  String? get lastExportFilename => _prefs.getString(_keyFilename);
}
