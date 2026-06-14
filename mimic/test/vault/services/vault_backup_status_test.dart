// test/vault/services/vault_backup_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/vault/services/vault_backup_status.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh state is out of date', () async {
    final status = await VaultBackupStatus.init();
    expect(status.isBackupOutOfDate(0), isTrue);
    expect(status.isBackupOutOfDate(5), isTrue);
  });

  test('after recordExport with current count, up to date', () async {
    final status = await VaultBackupStatus.init();
    await status.recordExport(5, '/path/to/backup.mimic');
    
    expect(status.isBackupOutOfDate(5), isFalse);
    expect(status.lastExportFilename, '/path/to/backup.mimic');
  });

  test('add an item so current count is different, out of date again', () async {
    final status = await VaultBackupStatus.init();
    await status.recordExport(5, '/path/to/backup.mimic');
    
    expect(status.isBackupOutOfDate(6), isTrue);
    expect(status.isBackupOutOfDate(4), isTrue); // deletion also marks out of date
  });
}
