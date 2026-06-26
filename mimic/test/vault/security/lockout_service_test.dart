import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/security/lockout_service.dart';
import 'package:mimic/core/services/platform_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _storage = {};
  bool intruderStorageUntouched = true;

  @override
  Future<String?> secureRead(String key) async => _storage[key];

  @override
  Future<void> secureWrite(String key, String value) async {
    if (key.startsWith('intruder') || key.startsWith('break_in')) {
      intruderStorageUntouched = false;
    }
    _storage[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    if (key.startsWith('intruder') || key.startsWith('break_in')) {
      intruderStorageUntouched = false;
    }
    _storage.remove(key);
  }

  @override
  Future<void> deleteFile(String path) async {}

  @override
  bool isWeb() => false;

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

void main() {
  group('LockoutService', () {
    late FakePlatformService fakeStorage;
    late FakeMonotonicClock fakeClock;
    late LockoutService service;

    setUp(() {
      fakeStorage = FakePlatformService();
      fakeClock = FakeMonotonicClock();
      service = LockoutService(fakeStorage, fakeClock);
    });

    test('cooldownForAttempts curve', () {
      expect(cooldownForAttempts(1), Duration.zero);
      expect(cooldownForAttempts(4), Duration.zero);
      expect(cooldownForAttempts(5), const Duration(seconds: 30));
      expect(cooldownForAttempts(6), const Duration(seconds: 60));
      expect(cooldownForAttempts(7), const Duration(minutes: 5));
      expect(cooldownForAttempts(8), const Duration(minutes: 15));
      expect(cooldownForAttempts(9), const Duration(minutes: 30));
      expect(cooldownForAttempts(10), const Duration(minutes: 60));
      expect(cooldownForAttempts(11), const Duration(minutes: 60));
      expect(cooldownForAttempts(20), const Duration(minutes: 60));
    });

    test('remainingLockout - normal countdown (mocking past)', () async {
      final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
      final setWall = nowWall - 10000; // 10s ago
      final setElapsed = 1000;
      fakeClock.value = 11000; // 10s passed
      
      await fakeStorage.secureWrite('lockout_set_wall', setWall.toString());
      await fakeStorage.secureWrite('lockout_set_elapsed', setElapsed.toString());
      await fakeStorage.secureWrite('lockout_duration_ms', const Duration(seconds: 30).inMilliseconds.toString());

      final remaining = await service.remainingLockout();
      // Should be roughly 20s. Give a small tolerance of 1 second for test execution speed.
      expect(remaining.inMilliseconds, closeTo(20000, 1000));
    });

    test('remainingLockout - wall jumped FORWARD (early unlock attempt)', () async {
      final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
      final setWall = nowWall - 60000; // Wall jumped forward 60s
      final setElapsed = 1000;
      fakeClock.value = 11000; // Elapsed only advanced 10s
      
      await fakeStorage.secureWrite('lockout_set_wall', setWall.toString());
      await fakeStorage.secureWrite('lockout_set_elapsed', setElapsed.toString());
      await fakeStorage.secureWrite('lockout_duration_ms', const Duration(seconds: 30).inMilliseconds.toString());

      final remaining = await service.remainingLockout();
      // Wall says expired, but elapsed says 20s remaining. Should take max (elapsed).
      expect(remaining.inMilliseconds, closeTo(20000, 1000));
    });

    test('remainingLockout - wall jumped BACKWARD', () async {
      final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
      final setWall = nowWall + 60000; // Wall is in the future
      final setElapsed = 1000;
      fakeClock.value = 11000; // Elapsed advanced 10s
      
      await fakeStorage.secureWrite('lockout_set_wall', setWall.toString());
      await fakeStorage.secureWrite('lockout_set_elapsed', setElapsed.toString());
      await fakeStorage.secureWrite('lockout_duration_ms', const Duration(seconds: 30).inMilliseconds.toString());

      final remaining = await service.remainingLockout();
      // Wall is invalid, ignored. Elapsed says 20s. 
      expect(remaining.inMilliseconds, closeTo(20000, 1000));
    });

    test('remainingLockout - reboot (elapsed reset)', () async {
      final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
      final setWall = nowWall - 10000; // Wall advanced 10s
      final setElapsed = 50000; // Was at 50s
      fakeClock.value = 5000; // Rebooted, now at 5s (less than setElapsed)
      
      await fakeStorage.secureWrite('lockout_set_wall', setWall.toString());
      await fakeStorage.secureWrite('lockout_set_elapsed', setElapsed.toString());
      await fakeStorage.secureWrite('lockout_duration_ms', const Duration(seconds: 30).inMilliseconds.toString());

      final remaining = await service.remainingLockout();
      // Elapsed is invalid, falls back to wall (20s remaining)
      expect(remaining.inMilliseconds, closeTo(20000, 1000));
    });

    test('remainingLockout - both clocks past duration', () async {
      final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
      final setWall = nowWall - 60000; // 60s ago
      final setElapsed = 1000;
      fakeClock.value = 61000; // 60s ago
      
      await fakeStorage.secureWrite('lockout_set_wall', setWall.toString());
      await fakeStorage.secureWrite('lockout_set_elapsed', setElapsed.toString());
      await fakeStorage.secureWrite('lockout_duration_ms', const Duration(seconds: 30).inMilliseconds.toString());

      final remaining = await service.remainingLockout();
      expect(remaining, Duration.zero);
    });

    test('reset clears lockout keys + wrong_attempts, intruder untouched', () async {
      await fakeStorage.secureWrite('lockout_set_wall', '123');
      await fakeStorage.secureWrite('lockout_set_elapsed', '123');
      await fakeStorage.secureWrite('lockout_duration_ms', '123');
      await fakeStorage.secureWrite('wrong_attempts', '5');
      await fakeStorage.secureWrite('intruder_photo_1', 'blob');

      fakeStorage.intruderStorageUntouched = true;
      await service.reset();

      expect(await fakeStorage.secureRead('lockout_set_wall'), isNull);
      expect(await fakeStorage.secureRead('lockout_set_elapsed'), isNull);
      expect(await fakeStorage.secureRead('lockout_duration_ms'), isNull);
      expect(await fakeStorage.secureRead('wrong_attempts'), isNull);
      expect(await fakeStorage.secureRead('intruder_photo_1'), 'blob');
      expect(fakeStorage.intruderStorageUntouched, isTrue);
    });
  });
}
