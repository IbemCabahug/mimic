// test/vault/security/auto_lock_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  final Map<String, Uint8List> fileStore = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    fileStore[path] = data;
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => fileStore[path];

  @override
  Future<void> deleteFile(String path) async {
    fileStore.remove(path);
  }

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

void main() {
  late FakePlatformService fakePlatform;

  setUp(() {
    AutoLock().dispose();
    fakePlatform = FakePlatformService();
  });

  tearDown(() {
    AutoLock().dispose();
  });

  group('AutoLock Reference Counting & Policy', () {
    // -------------------------------------------------------------------------
    // T1: two suspends then one resume leaves the pause still active.
    // -------------------------------------------------------------------------
    testWidgets('T1: two suspends then one resume leaves the pause still active', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(1));
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(2));
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(1));
      expect(AutoLock().isSuspended, isTrue);

      // Wait 70 seconds. The pause is still active so vault remains unlocked.
      await tester.pump(const Duration(seconds: 70));
      expect(crypto.isUnlocked, isTrue);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T2: two suspends then two resumes releases the pause and restarts the idle timer.
    // -------------------------------------------------------------------------
    testWidgets('T2: two suspends then two resumes releases the pause and restarts the idle timer', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().suspend();
      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(2));

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(1));
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      // Wait 6 minutes (> 5 min idle timeout). Idle timer has restarted and locks vault.
      await tester.pump(const Duration(minutes: 6));
      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T3: resume() called more times than suspend() does not drive the counter negative and does not crash.
    // -------------------------------------------------------------------------
    test('T3: resume() called more times than suspend() does not drive the counter negative and does not crash', () {
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      // Call resume when count is 0
      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      // Suspend once then resume twice
      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(1));
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().resume();
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T4: a second suspend() while already paused does not re-arm or extend the 30-minute ceiling.
    // -------------------------------------------------------------------------
    testWidgets('T4: a second suspend() while already paused does not re-arm or extend the 30-minute ceiling', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      // First suspend at t = 0 (arms 30-minute ceiling timer)
      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(1));

      // Advance time by 20 minutes (10 minutes remaining on ceiling)
      await tester.pump(const Duration(minutes: 20));
      expect(crypto.isUnlocked, isTrue);

      // Second suspend at t = 20m. Must NOT extend ceiling by another 30m.
      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(2));

      // Advance time by 11 minutes (total 31m from first suspend, 11m from second suspend).
      // Since the ceiling was not extended, 31m >= 30m causes ceiling timer to fire.
      await tester.pump(const Duration(minutes: 11));

      // Drain asynchronous lock tasks if any
      await tester.runAsync(() async {
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (!crypto.isUnlocked) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            break;
          }
        }
      });

      expect(crypto.isUnlocked, isFalse);
      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T5: with no pause held, the vault does NOT lock after 4 minutes of foreground idle, and DOES lock after 6 minutes.
    // -------------------------------------------------------------------------
    testWidgets('T5: with no pause held, the vault does NOT lock after 4 minutes of foreground idle, and DOES lock after 6 minutes', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      // Advance time by 4 minutes (< 5 min timeout): should NOT lock
      await tester.pump(const Duration(minutes: 4));
      expect(crypto.isUnlocked, isTrue);

      // Advance time by 2 more minutes (total 6 minutes > 5 min timeout): DOES lock
      await tester.pump(const Duration(minutes: 2));
      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T6: with no pause held, backgrounded for 70 seconds then resumed -> locked.
    // -------------------------------------------------------------------------
    testWidgets('T6: with no pause held, backgrounded for 70 seconds then resumed -> locked', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);

      await tester.pump();
      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T7: with a read-pause held (suspend() called), backgrounded for 70 seconds then resumed -> LOCKED.
    // -------------------------------------------------------------------------
    testWidgets('T7: with a read-pause held (suspend() called), backgrounded for 70 seconds then resumed -> LOCKED', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().suspend();
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);

      await tester.pump();
      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T8: with a protected operation in flight, backgrounded for 70 seconds then resumed -> NOT locked, and still not locked at 5 minutes of background time.
    // -------------------------------------------------------------------------
    testWidgets('T8: with a protected operation in flight, backgrounded for 70 seconds then resumed -> NOT locked, and still not locked at 5 minutes of background time', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().beginProtectedOperation();
      expect(AutoLock().isProtectedOperationInFlight, isTrue);

      // Backgrounded for 70 seconds (> 1 min grace, but protected operation prevents lock)
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(crypto.isUnlocked, isTrue);

      // Backgrounded for 5 minutes (> 1 min grace, still protected)
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(minutes: 5)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(crypto.isUnlocked, isTrue);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T9: beginProtectedOperation twice then endProtectedOperation once leaves the operation state active; a second end releases it; extra ends do not go negative.
    // -------------------------------------------------------------------------
    test('T9: beginProtectedOperation twice then endProtectedOperation once leaves the operation state active; a second end releases it; extra ends do not go negative', () {
      expect(AutoLock().isProtectedOperationInFlight, isFalse);
      expect(AutoLock().protectedOperationCount, equals(0));

      AutoLock().endProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(0));
      expect(AutoLock().isProtectedOperationInFlight, isFalse);

      AutoLock().beginProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(1));
      expect(AutoLock().isProtectedOperationInFlight, isTrue);
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().beginProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(2));
      expect(AutoLock().isProtectedOperationInFlight, isTrue);
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().endProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(1));
      expect(AutoLock().isProtectedOperationInFlight, isTrue);
      expect(AutoLock().isSuspended, isTrue);

      AutoLock().endProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(0));
      expect(AutoLock().isProtectedOperationInFlight, isFalse);
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().endProtectedOperation();
      expect(AutoLock().protectedOperationCount, equals(0));
      expect(AutoLock().isProtectedOperationInFlight, isFalse);
      expect(AutoLock().isSuspended, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T10: with a read-pause held and no protected operation, the 30-minute ceiling still fires and locks the vault.
    // -------------------------------------------------------------------------
    testWidgets('T10: with a read-pause held and no protected operation, the 30-minute ceiling still fires and locks the vault', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().suspend();
      expect(AutoLock().isSuspended, isTrue);

      // Advance time to the 30-minute ceiling
      await tester.pump(AutoLock.suspendCeiling);

      await tester.runAsync(() async {
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (!crypto.isUnlocked) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            break;
          }
        }
      });

      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T11: a suspend() with no matching resume(), followed by init(), leaves the counter at zero and the idle timer working — the M19 safety net.
    // -------------------------------------------------------------------------
    testWidgets('T11: a suspend() with no matching resume(), followed by init(), leaves the counter at zero and the idle timer working — the M19 safety net', (WidgetTester tester) async {
      late VaultCrypto crypto;

      // Abandoned suspend prior to init
      AutoLock().suspend();
      expect(AutoLock().suspendCount, equals(1));
      expect(AutoLock().isSuspended, isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      // Clean slate verification after init()
      expect(AutoLock().suspendCount, equals(0));
      expect(AutoLock().isSuspended, isFalse);
      expect(AutoLock().isProtectedOperationInFlight, isFalse);

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      // 4 minutes idle: not locked
      await tester.pump(const Duration(minutes: 4));
      expect(crypto.isUnlocked, isTrue);

      // 2 more minutes idle (total 6m > 5m): locked
      await tester.pump(const Duration(minutes: 2));
      expect(crypto.isUnlocked, isFalse);

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T12: a protected operation released while still backgrounded (picker cancelled) does NOT lock on resume - the M22 ordering fix.
    // -------------------------------------------------------------------------
    testWidgets('T12: a protected operation released while still backgrounded (picker cancelled) does NOT lock on resume - the M22 ordering fix', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().beginProtectedOperation();
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().endProtectedOperation();
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(crypto.isUnlocked, isTrue,
          reason: 'Protected operation active at moment of pause must exempt the trip from background lock even if released before resume');

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T13: with no protected operation at the moment of backgrounding, 70 seconds in the background still locks.
    // -------------------------------------------------------------------------
    testWidgets('T13: with no protected operation at the moment of backgrounding, 70 seconds in the background still locks', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(crypto.isUnlocked, isFalse,
          reason: 'Without a protected operation at pause, 70s in background must lock the vault');

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T14: the recorded protected-operation flag is cleared after one resume and does not protect a later background trip.
    // -------------------------------------------------------------------------
    testWidgets('T14: the recorded protected-operation flag is cleared after one resume and does not protect a later background trip', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      // First trip: protected operation held at pause, released while backgrounded
      AutoLock().beginProtectedOperation();
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().endProtectedOperation();
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(crypto.isUnlocked, isTrue,
          reason: 'First trip was protected at pause time so vault remains unlocked');

      // Second trip: no protected operation, backgrounded again for 70 seconds
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(crypto.isUnlocked, isFalse,
          reason: 'Second trip without protected operation must lock after 70s background');

      AutoLock().dispose();
    });

    // -------------------------------------------------------------------------
    // T15: a protected trip that exceeds the 30-minute ceiling still locks.
    // -------------------------------------------------------------------------
    testWidgets('T15: a protected trip that exceeds the 30-minute ceiling still locks', (WidgetTester tester) async {
      late VaultCrypto crypto;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                crypto = ref.read(vaultCryptoProvider);
                AutoLock().init(context, ref);
                return const AutoLockWrapper(
                  child: Text('VAULT_CONTENT'),
                );
              },
            ),
          ),
        ),
      );

      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      AutoLock().beginProtectedOperation();
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(minutes: 31)));
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(crypto.isUnlocked, isFalse,
          reason: 'The protected-operation exemption from the 1-minute background rule is bounded by the 30-minute suspend ceiling');

      AutoLock().dispose();
    });
  });
}
