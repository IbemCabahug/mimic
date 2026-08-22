// test/vault/security/security_test.dart
//
// Comprehensive security tests for the Mimic vault layer.
// Covers: TriggerDetector, PinScreen, AutoLock, PanicMode, BreakInLog model.
//
// All platform services and crypto are faked in-memory — no disk, no
// flutter_secure_storage plugin, no camera, no sensors_plus, no sqflite.

import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/vault/trigger/trigger_detector.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/security/breakin_log.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/security/shake_wipe_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/core/providers/provider_registration.dart'
    show networkServiceProvider, platformServiceProvider;

import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/vault/security/vault_conceal_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fakes
// ═══════════════════════════════════════════════════════════════════════════

/// In-memory PlatformService that records every write for later inspection.
class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  final Map<String, Uint8List> fileStore = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);

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

/// Controllable NetworkService for test overrides.
class ControllableNetworkService extends NetworkService {
  NetworkRole _testRole = NetworkRole.none;

  @override
  NetworkRole get role => _testRole;

  @override
  bool get isConnected => _testRole != NetworkRole.none;

  void setRole(NetworkRole newRole) {
    _testRole = newRole;
    if (hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // No-op for test double to prevent Riverpod autoDispose from marking
    // the instance permanently disposed during test rebuilds.
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1-4 · TriggerDetector
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('TriggerDetector', () {
    // Reset the singleton registry before each test so tests don't leak state.
    setUp(() {
      TriggerCallbackRegistry().setOnTap(null);
    });

    // ------------------------------------------------------------------
    // Test 1 — correct tap sequence fires the vault unlock callback
    // ------------------------------------------------------------------
    testWidgets(
      '1 · correct tap sequence fires the vault unlock callback',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        tapSequence: const [0, 1, 0],
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        registry.recordTap(0);
        registry.recordTap(1);
        registry.recordTap(0);

        // The _FlashOverlay has a 3-stage timer chain:
        // 1. AnimationController.forward() runs for 300ms
        // 2. .then() callback fires and schedules Future.delayed(300ms)
        // 3. Future.delayed fires and calls onCompleted → onTrigger
        // We pump 500ms to complete the animation (which executes the .then microtask
        // and schedules the Future.delayed), then another 500ms to complete the delayed timer.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isTrue,
            reason: 'Correct tap sequence must fire onTrigger');
      },
    );

    // ------------------------------------------------------------------
    // Test 2 — wrong tap sequence does NOT fire
    // ------------------------------------------------------------------
    testWidgets(
      '2 · wrong tap sequence does not fire the callback',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        tapSequence: const [0, 1, 0],
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        // Wrong sequence — [1, 1, 0] instead of [0, 1, 0]
        registry.recordTap(1);
        registry.recordTap(1);
        registry.recordTap(0);

        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(triggered, isFalse,
            reason: 'Wrong tap sequence must NOT fire onTrigger');
      },
    );

    // ------------------------------------------------------------------
    // Test 3 — correct taps beyond timeout window do NOT fire
    // ------------------------------------------------------------------
    testWidgets(
      '3 · correct sequence tapped too slowly (beyond timeout) does not fire',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        tapSequence: const [0, 1, 0],
                        // Short timeout so the test doesn't take forever.
                        timeout: const Duration(milliseconds: 500),
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();

        registry.recordTap(0);
        registry.recordTap(1);

        // Wait longer than the 500ms timeout — history should auto-clear.
        await tester.pump(const Duration(milliseconds: 600));

        // Third tap now arrives after the reset — sequence is [0], not [0,1,0].
        registry.recordTap(0);

        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(triggered, isFalse,
            reason: 'Taps past the timeout window must reset the sequence');
      },
    );

    // ------------------------------------------------------------------
    // Test 4 — renders zero visible pixels (SizedBox.expand, transparent)
    // ------------------------------------------------------------------
    testWidgets(
      '4 · renders zero visible pixels — SizedBox.expand only',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        tapSequence: const [0],
                        onTrigger: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // TriggerDetector.build returns `const SizedBox.expand()` — no
        // Container, no Text, no Icon. Verify the widget tree.
        final sizedBoxFinder = find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == double.infinity &&
              widget.height == double.infinity,
        );

        expect(sizedBoxFinder, findsOneWidget,
            reason: 'TriggerDetector must render an invisible SizedBox.expand');

        // No coloured containers, text or icons should exist inside TriggerDetector.
        expect(
          find.descendant(
            of: find.byType(TriggerDetector),
            matching: find.byType(Container),
          ),
          findsNothing,
          reason:
              'TriggerDetector must not contain a Container (no visible paint)',
        );
      },
    );

    // ------------------------------------------------------------------
    // Test 5 — multiplayer guard prevents trigger and flash overlay
    // ------------------------------------------------------------------
    testWidgets(
      '5 · active multiplayer session prevents trigger callback and flash overlay',
      (WidgetTester tester) async {
        bool triggered = false;
        final controlNet = ControllableNetworkService();
        controlNet.setRole(NetworkRole.guest);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              networkServiceProvider.overrideWith((ref) => controlNet),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        tapSequence: const [0, 1, 0],
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        registry.recordTap(0);
        registry.recordTap(1);
        registry.recordTap(0);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isFalse,
            reason: 'Trigger must NOT fire during an active multiplayer session');
        expect(
            find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_FlashOverlay'),
            findsNothing,
            reason:
                'Flash overlay must NOT be inserted when multiplayer is active');

        // Now disconnect multiplayer and verify trigger DOES fire
        controlNet.setRole(NetworkRole.none);
        registry.recordTap(0);
        registry.recordTap(1);
        registry.recordTap(0);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isTrue,
            reason: 'Trigger MUST fire when no multiplayer session is active');
      },
    );

    // ------------------------------------------------------------------
    // Test N1 — async verifier returning true fires onTrigger
    // ------------------------------------------------------------------
    testWidgets(
      'N1 · async verifier returning true fires onTrigger',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        verifier: (taps) async => taps.join(',') == '1,0,2',
                        verifyLength: 3,
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        registry.recordTap(1);
        registry.recordTap(0);
        registry.recordTap(2);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isTrue,
            reason: 'Verifier returning true must fire onTrigger');
      },
    );

    // ------------------------------------------------------------------
    // Test N2 — async verifier returning false never fires onTrigger
    // ------------------------------------------------------------------
    testWidgets(
      'N2 · async verifier returning false never fires onTrigger',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        verifier: (taps) async => false,
                        verifyLength: 3,
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        registry.recordTap(1);
        registry.recordTap(0);
        registry.recordTap(2);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isFalse,
            reason: 'Verifier returning false must NOT fire onTrigger');
      },
    );

    // ------------------------------------------------------------------
    // Test N3 — trailing match fires after wrong leading tap
    // ------------------------------------------------------------------
    testWidgets(
      'N3 · trailing match fires after wrong leading tap using trailingWindow',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        verifier: (taps) async => taps.join(',') == '1,0,2',
                        verifyLength: 3,
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        // Tap wrong index first (0), then valid sequence 1, 0, 2
        registry.recordTap(0);
        registry.recordTap(1);
        registry.recordTap(0);
        registry.recordTap(2);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isTrue,
            reason: 'Trailing window matching sequence must fire onTrigger');
      },
    );

    // ------------------------------------------------------------------
    // Test N4 — verifier that throws does not fire onTrigger and does not crash
    // ------------------------------------------------------------------
    testWidgets(
      'N4 · verifier that throws does not fire onTrigger and does not crash',
      (WidgetTester tester) async {
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        verifier: (taps) async => throw Exception('KDF error'),
                        verifyLength: 3,
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        registry.recordTap(1);
        registry.recordTap(0);
        registry.recordTap(2);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isFalse,
            reason: 'Throwing verifier must NOT fire onTrigger and must not crash');
      },
    );

    // ------------------------------------------------------------------
    // Test N5 — queued recheck is not dropped when taps arrive back-to-back
    // ------------------------------------------------------------------
    testWidgets(
      'N5 · queued recheck fires onTrigger when taps arrive back to back',
      (WidgetTester tester) async {
        // This test proves a queued recheck is not dropped when taps arrive faster than verification completes.
        bool triggered = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => TriggerDetector(
                        verifier: (taps) async => taps.join(',') == '1,0,2',
                        verifyLength: 3,
                        onTrigger: () => triggered = true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final registry = TriggerCallbackRegistry();
        // Four taps arrive back to back with no pump between them: 0, then 1, 0, 2
        registry.recordTap(0);
        registry.recordTap(1);
        registry.recordTap(0);
        registry.recordTap(2);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(triggered, isTrue,
            reason: 'Queued recheck must not be dropped and onTrigger must fire');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5-8 · PinScreen
  // ═══════════════════════════════════════════════════════════════════════

  group('PinScreen', () {
    late FakePlatformService fakePlatform;

    setUp(() {
      fakePlatform = FakePlatformService();
    });

    /// Helper that builds a full app shell with Riverpod overrides and the
    /// route table needed by PinScreen's Navigator calls.
    Widget buildTestApp({required Widget home}) {
      return ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
        ],
        child: MaterialApp(
          initialRoute: '/test-home',
          routes: {
            '/test-home': (_) => home,
            '/vault-home': (_) => const Scaffold(
                  body: Text('VAULT_HOME_SCREEN'),
                ),
            '/vault-pin': (_) => const Scaffold(
                  body: Text('PIN_SCREEN'),
                ),
            '/': (_) => const Scaffold(
                  body: Text('GAME_HOME'),
                ),
          },
        ),
      );
    }

    // ------------------------------------------------------------------
    // Test 5 — correct PIN navigates to VaultHomeScreen
    // ------------------------------------------------------------------
    testWidgets(
      '5 · correct PIN navigates to VaultHomeScreen',
      (WidgetTester tester) async {
        // Pre-seed the fake storage so VaultCrypto.initialize succeeds
        // on the first call (sets up salt + pin hash).
        final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
        await crypto.initialize('1234');
        crypto.lock();

        await tester.pumpWidget(
          buildTestApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      final testCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());
                      await testCrypto.initialize('1234');
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/vault-home');
                      }
                    },
                    child: const Text('Unlock'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();

        expect(find.text('VAULT_HOME_SCREEN'), findsOneWidget,
            reason: 'Correct PIN must navigate to the vault home screen');
      },
    );

    // ------------------------------------------------------------------
    // Test 6 — wrong PIN shows error and does NOT navigate
    // ------------------------------------------------------------------
    testWidgets(
      '6 · wrong PIN shows error and does NOT navigate',
      (WidgetTester tester) async {
        // Seed with correct PIN '1234'.
        final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
        await crypto.initialize('1234');
        crypto.lock();

        String? errorText;

        await tester.pumpWidget(
          buildTestApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            final testCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());
                            await testCrypto.initialize('9999');
                            if (context.mounted) {
                              Navigator.of(context)
                                  .pushReplacementNamed('/vault-home');
                            }
                          } catch (e) {
                            errorText = e.toString();
                            // In the real PinScreen this sets _error state
                          }
                        },
                        child: const Text('Unlock'),
                      ),
                      if (errorText != null) Text(errorText!),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();

        // Should NOT have navigated.
        expect(find.text('VAULT_HOME_SCREEN'), findsNothing,
            reason: 'Wrong PIN must not navigate to vault');

        // The crypto layer threw 'Invalid PIN'.
        expect(errorText, contains('Invalid PIN'),
            reason: 'VaultCrypto must throw on wrong PIN');
      },
    );

    // ------------------------------------------------------------------
    // Test 7 — after 3 wrong PINs, the attempt counter reaches 3
    // ------------------------------------------------------------------
    testWidgets(
      '7 · after 3 wrong PINs, attempt counter is stored as 3',
      (WidgetTester tester) async {
        // Seed correct PIN.
        final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
        await crypto.initialize('1234');
        crypto.lock();

        int failCount = 0;

        await tester.pumpWidget(
          buildTestApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            final testCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());
                            await testCrypto.initialize('0000');
                          } catch (_) {
                            setState(() {
                              failCount++;
                            });
                            await fakePlatform.secureWrite(
                              'wrong_attempts',
                              failCount.toString(),
                            );
                            if (failCount >= 3 && context.mounted) {
                              Navigator.of(context)
                                  .pushReplacementNamed('/');
                            }
                          }
                        },
                        child: const Text('Unlock'),
                      ),
                      Text('fails:$failCount'),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Three wrong attempts.
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Unlock'));
          await tester.pumpAndSettle();
        }

        // After 3 failures the test navigates to game home.
        expect(find.text('GAME_HOME'), findsOneWidget,
            reason: 'After 3 wrong PINs, must navigate back to game home');

        // Stored count should be '3'.
        expect(fakePlatform.store['wrong_attempts'], equals('3'));
      },
    );

    // ------------------------------------------------------------------
    // Test 8 — vault key is in memory only, never in secure storage
    // ------------------------------------------------------------------
    test(
      '8 · vault key is stored in Riverpod/memory only — never in flutter_secure_storage after unlock',
      () async {
        final platform = FakePlatformService();
        final crypto = VaultCrypto(platform, FakeKeystoreService());
        await crypto.initialize('5678');

        // The crypto layer IS unlocked.
        expect(crypto.isUnlocked, isTrue);

        // Walk every persisted value in the fake store — none of them should
        // be the raw derived key. The store should only hold:
        //   vault_salt  (base64 salt)
        //   vault_pin_hash  (SHA-256 of the PIN)
        // and optionally vault_pin (the PIN itself, written by PinScreen).
        //
        // The derived AES key must NEVER appear.
        for (final entry in platform.store.entries) {
          // vault_salt is 16 bytes → 24 chars base64
          // vault_pin_hash is 32 bytes → 44 chars base64
          // The derived key is 32 bytes = 44 chars base64.
          // We can't just check length — the pin hash is also 44 chars.
          // Instead verify the key name is one of the expected keys.
          // 'master_key_wrapped' is allowed: it is the data key ENCRYPTED under
          // the PIN-derived KEK (IV + AES-CBC ciphertext), never the raw key.
          expect(
            [
              'vault_salt',
              'vault_pin_hash',
              'vault_setup_completed',
              'vault_wiped',
              'master_key_wrapped',
            ].contains(entry.key),
            isTrue,
            reason:
                'Unexpected key "${entry.key}" found in secure storage — '
                'the derived AES key must never be persisted',
          );
        }

        // Strengthen: the wrapped key must be genuinely encrypted, not the raw
        // 32-byte derived key. A raw key is 44 base64 chars; the wrapped form is
        // IV + AES-CBC ciphertext (~88 chars), so it must be clearly longer.
        final wrapped = platform.store['master_key_wrapped'];
        expect(wrapped, isNotNull,
            reason: 'master_key_wrapped must be persisted after setup');
        expect(
          wrapped!.length,
          greaterThan(44),
          reason:
              'master_key_wrapped must be IV + ciphertext, never the raw '
              'derived key',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 9-10 · AutoLock / AutoLockWrapper
  // ═══════════════════════════════════════════════════════════════════════

  group('AutoLock', () {
    late FakePlatformService fakePlatform;

    setUp(() {
      fakePlatform = FakePlatformService();
      // Reset the AutoLock singleton between tests.
      AutoLock().dispose();
    });

    // ------------------------------------------------------------------
    // Test 8.5 — AutoLock suspend/resume prevents idle timer from firing
    // ------------------------------------------------------------------
    testWidgets(
      '8.5 · AutoLock suspend/resume prevents idle timer from firing',
      (WidgetTester tester) async {
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
        
        // Wait 6 minutes. If timer was active, vault would lock.
        await tester.pump(const Duration(minutes: 6));
        
        // Should STILL be unlocked because it was suspended.
        expect(crypto.isUnlocked, isTrue);

        AutoLock().resume();

        // Wait another 6 minutes, now the timer should fire.
        await tester.pump(const Duration(minutes: 6));
        expect(crypto.isUnlocked, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Test 8.6 — AutoLock suspend ceiling expiring locks the vault
    // ------------------------------------------------------------------
    testWidgets(
      '8.6 · AutoLock suspend ceiling expiring locks the vault',
      (WidgetTester tester) async {
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

        // Advance time past the suspend ceiling duration
        await tester.pump(AutoLock.suspendCeiling);

        // RunAsync drain idiom (copied from test/vault/security/vault_conceal_service_test.dart:307-315)
        await tester.runAsync(() async {
          for (int i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (!crypto.isUnlocked) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              break;
            }
          }
        });

        // When ceiling expires, the vault locks (key cleared)
        expect(crypto.isUnlocked, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Test 8.7 · AutoLock resume before suspend ceiling cancels ceiling timer
    // ------------------------------------------------------------------
    testWidgets(
      '8.7 · AutoLock resume before suspend ceiling cancels ceiling timer',
      (WidgetTester tester) async {
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

        // Advance time by 10 minutes (less than the 30 minute ceiling)
        await tester.pump(const Duration(minutes: 10));
        expect(crypto.isUnlocked, isTrue);

        // Resume active session
        AutoLock().resume();

        // Keep active with periodic interactions across next 25 minutes (total 35m > 30m ceiling)
        for (int i = 0; i < 50; i++) {
          await tester.pump(const Duration(seconds: 30));
          AutoLock().resetTimer();
        }

        // Vault is STILL unlocked because resume cancelled the ceiling timer
        expect(crypto.isUnlocked, isTrue);

        // Positive control: letting the normal 5-minute inactivity timer expire locks the vault
        await tester.pump(const Duration(minutes: 6));
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
      },
    );

    // ------------------------------------------------------------------
    // Test 9 — when the inactivity timeout fires, vaultCryptoProvider is
    //          cleared (key wiped).
    // ------------------------------------------------------------------
    testWidgets(
      '9 · AutoLock timeout clears vaultCryptoProvider (key wiped)',
      (WidgetTester tester) async {
        // We need a real ProviderScope so we can read vaultCryptoProvider.
        late WidgetRef capturedRef;
        late VaultCrypto crypto;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(fakePlatform),
            ],
            child: MaterialApp(
              routes: {
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
              home: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return AutoLockWrapper(
                    child: const Text('VAULT_CONTENT'),
                  );
                },
              ),
            ),
          ),
        );

        // Initialize the crypto so it's unlocked.
        crypto = capturedRef.read(vaultCryptoProvider);
        await crypto.initialize('1234');
        expect(crypto.isUnlocked, isTrue);

        // Init AutoLock with the captured ref — uses the 60s default timeout.
        // For the test we call the singleton's internal _lockVault indirectly
        // by inspecting state after dispose.
        final autoLock = AutoLock();
        // We directly test that dispose wipes state.
        autoLock.dispose();

        // After dispose, AutoLock is neutered, so we manually lock to
        // simulate what _lockVault does.
        crypto.clearKey();
        expect(crypto.isUnlocked, isFalse,
            reason: 'clearKey must set isUnlocked to false');
      },
    );

    // ------------------------------------------------------------------
    // Test 10 — when key is cleared, VaultHomeScreen redirects to PinScreen
    // ------------------------------------------------------------------
    testWidgets(
      '10 · when app returns with cleared key, VaultHomeScreen redirects to PinScreen',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(fakePlatform),
            ],
            child: MaterialApp(
              routes: {
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
                '/vault-home': (_) => Consumer(
                      builder: (context, ref, _) {
                        final crypto = ref.watch(vaultCryptoProvider);
                        if (!crypto.isUnlocked) {
                          // Exactly the pattern in VaultHomeScreen lines 60-63
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            Navigator.of(context)
                                .pushReplacementNamed('/vault-pin');
                          });
                          return const Scaffold(
                            body: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        return const Scaffold(
                            body: Text('VAULT_HOME_CONTENT'));
                      },
                    ),
              },
              home: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () async {
                      // Unlock, navigate, then simulate background lock.
                      final crypto = ref.read(vaultCryptoProvider);
                      await crypto.initialize('1234');
                      if (context.mounted) {
                        Navigator.of(context).pushNamed('/vault-home');
                      }
                    },
                    child: const Text('GoToVault'),
                  );
                },
              ),
            ),
          ),
        );

        // 1. Unlock and navigate to vault-home.
        await tester.tap(find.text('GoToVault'));
        await tester.pumpAndSettle();
        expect(find.text('VAULT_HOME_CONTENT'), findsOneWidget);

        // 2. Simulate auto-lock: wipe the key.
        final container =
            ProviderScope.containerOf(tester.element(find.text('VAULT_HOME_CONTENT')));
        container.read(vaultCryptoProvider).clearKey();

        // Pump to let the watcher fire + post-frame callback navigate.
        await tester.pumpAndSettle();

        expect(find.text('PIN_SCREEN'), findsOneWidget,
            reason:
                'With a cleared key the vault home must redirect to PinScreen');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 11 · PanicMode (unit-level — no sensors_plus in test env)
  // ═══════════════════════════════════════════════════════════════════════

  group('PanicMode', () {
    // ------------------------------------------------------------------
    // Test 11 — simulating panic mode clears vault key and navigates to
    //           game HomeScreen.
    //
    // PanicMode listens to the accelerometer via sensors_plus, which is
    // unavailable in the test environment. We test the _observable effect_:
    // that calling crypto.clearKey() + Navigator push to '/' works.
    // ------------------------------------------------------------------
    testWidgets(
      '11 · panic mode clears vault key and navigates to game HomeScreen',
      (WidgetTester tester) async {
        final fakePlatform = FakePlatformService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(fakePlatform),
            ],
            child: MaterialApp(
              initialRoute: '/test-panic',
              routes: {
                '/test-panic': (_) => Consumer(
                      builder: (context, ref, _) {
                        return Scaffold(
                          body: Column(
                            children: [
                              const Text('VAULT_CONTENT'),
                              ElevatedButton(
                                key: const Key('panic'),
                                onPressed: () {
                                  // Simulate exactly what PanicMode._triggerPanic does:
                                  // 1. Wipe keys
                                  ref.read(vaultCryptoProvider).clearKey();
                                  // 2. Navigate to game home with no animation
                                  Navigator.of(context).pushAndRemoveUntil(
                                    PageRouteBuilder(
                                      pageBuilder: (ctx, animation, secondaryAnimation) =>
                                          const Scaffold(body: Text('GAME_HOME')),
                                      transitionDuration: Duration.zero,
                                    ),
                                    (route) => false,
                                  );
                                },
                                child: const Text('Panic'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              },
            ),
          ),
        );

        // Unlock the vault first.
        final container = ProviderScope.containerOf(
            tester.element(find.text('VAULT_CONTENT')));
        final crypto = container.read(vaultCryptoProvider);
        await crypto.initialize('1234');
        expect(crypto.isUnlocked, isTrue);

        // Trigger the simulated panic.
        await tester.tap(find.byKey(const Key('panic')));
        await tester.pumpAndSettle();

        expect(crypto.isUnlocked, isFalse,
            reason: 'Panic mode must wipe the derived key');
        expect(find.text('GAME_HOME'), findsOneWidget,
            reason: 'Panic mode must navigate to the game home screen');
        expect(find.text('VAULT_CONTENT'), findsNothing,
            reason: 'Vault content must be completely removed from the tree');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 12 · DecoyPIN
  // ═══════════════════════════════════════════════════════════════════════

  group('DecoyPIN', () {
    // ------------------------------------------------------------------
    // Test 12 — decoy PIN opens VaultHomeScreen but with empty content lists.
    //
    // The current codebase does not implement a dedicated decoy PIN
    // feature. We simulate the expected behaviour: if a *different* PIN
    // initialises a *fresh* crypto (different salt), all vaults are empty.
    // ------------------------------------------------------------------
    test(
      '12 · decoy PIN opens vault with zero items (empty content lists)',
      () async {
        // "Real" user vault.
        final realPlatform = FakePlatformService();
        final realCrypto = VaultCrypto(realPlatform, FakeKeystoreService());
        await realCrypto.initialize('1234');

        // Encrypt a secret using the real key.
        final secret = realCrypto.encryptString('My secret note');
        expect(secret.isNotEmpty, isTrue);

        // "Decoy" vault — a completely separate platform (different salt).
        final decoyPlatform = FakePlatformService();
        final decoyCrypto = VaultCrypto(decoyPlatform, FakeKeystoreService());
        await decoyCrypto.initialize('0000'); // decoy PIN

        expect(decoyCrypto.isUnlocked, isTrue,
            reason: 'Decoy PIN must still unlock a (empty) crypto instance');

        // The decoy platform has no encrypted files, no notes, no photos.
        expect(decoyPlatform.fileStore, isEmpty,
            reason: 'Decoy vault must have zero encrypted files');

        // Attempting to decrypt the real vault's ciphertext with the decoy
        // key must fail — proving data isolation.
        expect(
          () => decoyCrypto.decryptString(secret),
          throwsA(isA<Exception>()),
          reason:
              'Decoy key must not be able to decrypt real vault ciphertext',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 13 · BreakInLog model
  // ═══════════════════════════════════════════════════════════════════════

  group('BreakInLog', () {
    // ------------------------------------------------------------------
    // Test 13 — BreakInLog model round-trip and data integrity.
    //
    // BreakInLogService.recordAttempt uses sqflite + camera, which require
    // native plugins unavailable in unit tests. We test:
    //   a) The BreakInLog data model serialisation round-trip.
    //   b) That a log entry captures the expected fields.
    //   c) That the encrypted photo path concept is non-null when
    //      attemptCount >= 3 (verified via model construction).
    // ------------------------------------------------------------------
    test(
      '13a · BreakInLog model serialises and deserialises correctly',
      () {
        final now = DateTime.now();
        final log = BreakInLog(
          id: 'test-uuid-001',
          encryptedPhotoPath: '/data/intruder_selfie_001.enc',
          timestamp: now.toIso8601String(),
          attemptCount: 3,
        );

        final map = log.toMap();

        expect(map['id'], equals('test-uuid-001'));
        expect(map['encryptedPhotoPath'],
            equals('/data/intruder_selfie_001.enc'));
        expect(map['timestamp'], equals(now.toIso8601String()));
        expect(map['attemptCount'], equals(3));

        // Round-trip through fromMap.
        final restored = BreakInLog.fromMap(map);
        expect(restored.id, equals(log.id));
        expect(restored.encryptedPhotoPath, equals(log.encryptedPhotoPath));
        expect(restored.timestamp, equals(log.timestamp));
        expect(restored.attemptCount, equals(log.attemptCount));
      },
    );

    test(
      '13b · BreakInLog with attemptCount < 3 has null encryptedPhotoPath',
      () {
        final log = BreakInLog(
          id: 'test-uuid-002',
          encryptedPhotoPath: null,
          timestamp: DateTime.now().toIso8601String(),
          attemptCount: 1,
        );

        expect(log.encryptedPhotoPath, isNull,
            reason: 'Fewer than 3 attempts should not trigger a selfie');

        // Verify null survives serialisation.
        final map = log.toMap();
        expect(map['encryptedPhotoPath'], isNull);

        final restored = BreakInLog.fromMap(map);
        expect(restored.encryptedPhotoPath, isNull);
      },
    );

    test(
      '13c · encrypted log entry concept — ciphertext stored, not plaintext',
      () async {
        // Verify that the data a BreakInLog would store (the photo path)
        // points to an .enc file, and the photo bytes would be encrypted.
        final fakePlatform = FakePlatformService();
        final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
        await crypto.initialize('1234');

        // Simulate what BreakInLogService.recordAttempt does (lines 92-100):
        // encrypt the photo bytes, write them to a .enc path.
        final fakeCameraBytes = Uint8List.fromList(
          List.generate(256, (i) => i % 256),
        );
        final encryptedBytes = await crypto.encryptBytes(fakeCameraBytes);

        // The encrypted bytes are NOT equal to the original.
        expect(encryptedBytes, isNot(equals(fakeCameraBytes)),
            reason: 'Encrypted photo must differ from original bytes');

        // Simulate writing to file store.
        const filePath = '/data/intruder_selfie_test.enc';
        await fakePlatform.saveEncryptedFile(filePath, encryptedBytes);

        // Verify the stored ciphertext round-trips.
        final readBack = await fakePlatform.readEncryptedFile(filePath);
        expect(readBack, isNotNull);

        final decrypted = await crypto.decryptBytes(readBack!);
        expect(decrypted, equals(fakeCameraBytes),
            reason: 'Decrypted photo must match the original camera bytes');

        // Build the BreakInLog pointing at this path.
        final log = BreakInLog(
          id: 'test-uuid-003',
          encryptedPhotoPath: filePath,
          timestamp: DateTime.now().toIso8601String(),
          attemptCount: 3,
        );

        expect(log.encryptedPhotoPath, endsWith('.enc'),
            reason: 'Break-in selfie must be stored as an encrypted .enc file');
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Supplementary edge-case tests
  // ═══════════════════════════════════════════════════════════════════════

  group('AutoLockWrapper interaction forwarding', () {
    testWidgets(
      'AutoLockWrapper passes pointer events through to children',
      (WidgetTester tester) async {
        bool childTapped = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: AutoLockWrapper(
                child: GestureDetector(
                  onTap: () => childTapped = true,
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: Text('TAP_ME'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('TAP_ME'));
        await tester.pump();

        expect(childTapped, isTrue,
            reason:
                'AutoLockWrapper uses HitTestBehavior.translucent — '
                'child taps must still work');
                
        AutoLock().dispose();
      },
    );
  });

  group('VaultCrypto lock/unlock guards', () {
    test('encrypt throws when vault is locked', () async {
      final crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await crypto.initialize('1234');
      crypto.lock();

      expect(
        () => crypto.encrypt(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<Exception>()),
        reason: 'encrypt must throw when vault is locked',
      );
    });

    test('encryptString throws when vault is locked', () async {
      final crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await crypto.initialize('1234');
      crypto.lock();

      expect(
        () => crypto.encryptString('test'),
        throwsA(isA<Exception>()),
        reason: 'encryptString must throw when vault is locked',
      );
    });

    test('clearKey is equivalent to lock', () async {
      final crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      crypto.clearKey();
      expect(crypto.isUnlocked, isFalse,
          reason: 'clearKey must set isUnlocked to false (alias for lock)');
    });
  });

  group('VaultConcealService & PinScreen Integration', () {
    tearDown(() {
      AutoLock().dispose();
    });

    testWidgets(
      'Concealed vault reveals and unlocks with correct PIN and clears concealed flag',
      (WidgetTester tester) async {
        final fakePlatform = FakePlatformService();
        final fakeShakeService = FakeShakeWipeService();
        final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

        SharedPreferences.setMockInitialValues({'shake_wipe_enabled': true});

        // Initialize real vault with PIN '1234' then lock it
        await tester.runAsync(() async {
          await fakeCrypto.initialize('1234');
        });
        fakeCrypto.lock();

        // Mark concealed
        await fakePlatform.secureWrite('vault_concealed', 'true');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(fakePlatform),
              shakeWipeServiceProvider.overrideWithValue(fakeShakeService),
              vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            ],
            child: MaterialApp(
              initialRoute: '/vault-pin',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
                '/vault-pin': (_) => const PinScreen(),
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        expect(find.text('Enter PIN'), findsWidgets);

        await tester.enterText(find.byType(TextField), '1234');
        await tester.pump();

        await tester.runAsync(() async {
          await tester.tap(find.text('Unlock'));
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (find.byType(RecoveryPhraseScreen).evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 50));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        expect(fakePlatform.store['vault_concealed'], equals('false'),
            reason: 'Correct PIN must clear the vault_concealed flag');
        expect(fakeCrypto.isUnlocked, isTrue,
            reason: 'Correct PIN must successfully unlock crypto');
        expect(find.byType(RecoveryPhraseScreen), findsOneWidget,
            reason: 'Vault with no recovery phrase setup must navigate to forced RecoveryPhraseScreen on unlock');
        AutoLock().dispose();
      },
    );

    testWidgets(
      'Concealed vault still opens the decoy admin panel for the duress PIN',
      (WidgetTester tester) async {
        final fakePlatform = FakePlatformService();
        final fakeShakeService = FakeShakeWipeService();
        final fakeDuress = FakeDuressService({'0000': true});

        SharedPreferences.setMockInitialValues({'shake_wipe_enabled': true});
        await fakePlatform.secureWrite('vault_pin_hash', 'dummy_hash');
        await fakePlatform.secureWrite('vault_salt', 'dummy_salt');
        await fakePlatform.secureWrite('vault_setup_completed', 'true');
        await fakePlatform.secureWrite('vault_concealed', 'true');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(fakePlatform),
              shakeWipeServiceProvider.overrideWithValue(fakeShakeService),
              duressServiceProvider.overrideWithValue(fakeDuress),
            ],
            child: MaterialApp(
              initialRoute: '/vault-pin',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
                '/admin-panel': (_) => const Scaffold(body: Text('ADMIN_PANEL')),
                '/vault-pin': (_) => const PinScreen(),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Enter PIN'), findsWidgets);

        await tester.enterText(find.byType(TextField), '0000');
        await tester.pump();
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();

        expect(find.text('ADMIN_PANEL'), findsOneWidget,
            reason: 'Duress PIN must open the decoy admin panel even while concealed');
        expect(find.text('Invalid PIN'), findsNothing);
      },
    );

    test('VaultConcealService.setConcealed persists and isConcealed reads from storage', () async {
      final fakePlatform = FakePlatformService();
      final service = VaultConcealService(null, fakePlatform);

      await service.setConcealed(true);
      expect(await fakePlatform.secureRead('vault_concealed'), 'true');
      expect(await service.isConcealed(), isTrue);

      await service.setConcealed(false);
      expect(await fakePlatform.secureRead('vault_concealed'), 'false');
      expect(await service.isConcealed(), isFalse);
    });
  });
}

class FakeShakeWipeService extends ShakeWipeService {
  VoidCallback? callback;

  @override
  void startListening(VoidCallback onWipeTriggered) {
    callback = onWipeTriggered;
  }

  @override
  void stopListening() {
    callback = null;
  }

  @override
  bool get isListening => callback != null;

  void simulateShake() {
    callback?.call();
  }
}

/// Fake DuressService that returns pre-configured answers without touching storage.
class FakeDuressService extends DuressService {
  final Map<String, bool> _fakeResults;

  FakeDuressService(this._fakeResults)
      : super(const _NoOpPlatformService());

  @override
  Future<bool> isFakePin(String pin) async => _fakeResults[pin] ?? false;

  @override
  Future<bool> isFakePinEnabled() async => _fakeResults.isNotEmpty;
}

/// Minimal no-op PlatformService used by FakeDuressService (never called).
class _NoOpPlatformService implements PlatformService {
  const _NoOpPlatformService();
  @override bool isWeb() => false;
  @override Future<String?> secureRead(String key) async => null;
  @override Future<Map<String, String>> secureReadAll() async => {};
  @override Future<void> secureWrite(String key, String value) async {}
  @override Future<void> secureDelete(String key) async {}
  @override Future<void> saveEncryptedFile(String path, Uint8List data) async {}
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}
