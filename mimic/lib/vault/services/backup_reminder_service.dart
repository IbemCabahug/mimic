// mimic/lib/vault/services/backup_reminder_service.dart
// pubspec: package_info_plus: ^8.0.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class BackupReminderService {
  static const String _lastBackupKey = 'last_backup_date';
  static const String _lastKnownVersionKey = 'last_known_version';
  static const int _remindAgainDays = 3;
  static const int _backupIntervalDays = 30;

  static bool _hasCheckedThisSession = false;

  static Future<void> checkAndShowReminder(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    if (kIsWeb) return;
    _hasCheckedThisSession = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final lastKnownVersion = prefs.getString(_lastKnownVersionKey);

      await prefs.setString(_lastKnownVersionKey, currentVersion);

      if (lastKnownVersion != null && lastKnownVersion != currentVersion) {
        if (!context.mounted) return;
        _showVersionUpdateDialog(context, currentVersion);
        return;
      }

      final lastBackupStr = prefs.getString(_lastBackupKey);
      if (lastBackupStr == null) {
        if (!context.mounted) return;
        _showBackupReminderDialog(context, null);
        return;
      }

      final lastBackup = DateTime.tryParse(lastBackupStr);
      if (lastBackup == null) {
        if (!context.mounted) return;
        _showBackupReminderDialog(context, null);
        return;
      }

      final daysSince = DateTime.now().difference(lastBackup).inDays;
      if (daysSince >= _backupIntervalDays) {
        if (!context.mounted) return;
        _showBackupReminderDialog(context, daysSince);
      }
    } catch (_) {}
  }

  static Future<void> markBackupCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
      final version = await _getCurrentVersion();
      await prefs.setString(_lastKnownVersionKey, version);
    } catch (_) {}
  }

  static Future<DateTime?> getLastBackupDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_lastBackupKey);
      if (str == null) return null;
      return DateTime.tryParse(str);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  static void _showVersionUpdateDialog(BuildContext context, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: VaultColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'App Updated',
          style: GoogleFonts.creepster(
            color: VaultColors.error,
            fontSize: 26,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          'Mimic has been updated to v$version. Your vault data is safe — but we recommend exporting a fresh backup to be sure.',
          style: const TextStyle(
            color: VaultColors.textPrimary,
            fontSize: 14,
            fontFamily: 'Inter',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _scheduleReminder();
            },
            child: Text(
              'REMIND ME LATER',
              style: GoogleFonts.creepster(
                color: VaultColors.textSecondary,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pushNamed('/vault-export');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'EXPORT NOW',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  static void _showBackupReminderDialog(BuildContext context, int? daysSince) {
    final dayText = daysSince == null ? 'It\'s been a while' : 'It\'s been $daysSince days';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: VaultColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Backup Reminder',
          style: GoogleFonts.creepster(
            color: VaultColors.error,
            fontSize: 26,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          '$dayText since your last vault backup. Export a .mimic file to keep your data safe.',
          style: const TextStyle(
            color: VaultColors.textPrimary,
            fontSize: 14,
            fontFamily: 'Inter',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _dismissReminder();
            },
            child: Text(
              'DISMISS',
              style: GoogleFonts.creepster(
                color: VaultColors.textSecondary,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pushNamed('/vault-export');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'EXPORT NOW',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _scheduleReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final remindDate = DateTime.now().add(const Duration(days: _remindAgainDays));
    await prefs.setString('backup_remind_date', remindDate.toIso8601String());
  }

  static Future<void> _dismissReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final remindDate = DateTime.now().add(Duration(days: _backupIntervalDays));
    await prefs.setString('backup_remind_date', remindDate.toIso8601String());
  }
}
