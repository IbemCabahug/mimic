// test/vault/screens/gesture_setup_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/screens/gesture_setup_screen.dart';
import 'package:mimic/vault/trigger/gesture_store.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map.unmodifiable(_data);
}

void main() {
  group('GestureSetupScreen', () {
    late FakeFlutterSecureStorage fakeStorage;
    late GestureStore store;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      store = GestureStore(storage: fakeStorage);
    });

    testWidgets('T1: instruction and heading visible on first build, continue disabled, no error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GestureSetupScreen(
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Heading and instruction visible
      expect(find.byKey(const ValueKey('gesture_heading')), findsOneWidget);
      expect(find.text('Choose your sequence'), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_instruction')), findsOneWidget);

      // CONTINUE button disabled
      final continueButton = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('gesture_continue')),
      );
      expect(continueButton.onPressed, isNull);

      // Error widget absent
      expect(find.byKey(const ValueKey('gesture_error')), findsNothing);

      // 3 dots and 3 candidate cards present
      expect(find.byKey(const ValueKey('gesture_dot_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_dot_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_dot_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_card_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_card_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_card_2')), findsOneWidget);
    });

    testWidgets('T2: all-identical sequence rejected without advancing or storing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GestureSetupScreen(
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card 1 three times
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();

      // CONTINUE is now enabled
      expect(
        tester.widget<ElevatedButton>(find.byKey(const ValueKey('gesture_continue'))).onPressed,
        isNotNull,
      );

      // Press CONTINUE
      await tester.tap(find.byKey(const ValueKey('gesture_continue')));
      await tester.pumpAndSettle();

      // Error widget displayed
      expect(find.byKey(const ValueKey('gesture_error')), findsOneWidget);

      // Heading remains in create phase
      expect(find.text('Choose your sequence'), findsOneWidget);

      // Nothing written to storage
      final storedData = await fakeStorage.readAll();
      expect(storedData.isEmpty, isTrue);
    });

    testWidgets('T3: mismatch between create and confirm returns to create with error and no writes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GestureSetupScreen(
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Create phase: Tap 0, 1, 2
      await tester.tap(find.byKey(const ValueKey('gesture_card_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_2')));
      await tester.pumpAndSettle();

      // Press CONTINUE -> moves to confirm phase
      await tester.tap(find.byKey(const ValueKey('gesture_continue')));
      await tester.pumpAndSettle();

      expect(find.text('Repeat your sequence'), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_error')), findsNothing);

      // Confirm phase: Tap mismatched 2, 1, 0
      await tester.tap(find.byKey(const ValueKey('gesture_card_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_0')));
      await tester.pumpAndSettle();

      // Press CONTINUE
      await tester.tap(find.byKey(const ValueKey('gesture_continue')));
      await tester.pumpAndSettle();

      // Expect error widget and return to create phase
      expect(find.byKey(const ValueKey('gesture_error')), findsOneWidget);
      expect(find.text('Choose your sequence'), findsOneWidget);

      // Nothing written to storage
      final storedData = await fakeStorage.readAll();
      expect(storedData.isEmpty, isTrue);
    });

    testWidgets('T4: matching sequence saves salted verifier, invokes callback, and verifies', (
      WidgetTester tester,
    ) async {
      int onCompleteCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: GestureSetupScreen(
            store: store,
            onComplete: () => onCompleteCallCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Create phase: Tap 1, 0, 2
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gesture_continue')));
      await tester.pumpAndSettle();

      expect(find.text('Repeat your sequence'), findsOneWidget);

      // Confirm phase: Tap identical 1, 0, 2 (Derivation 1 in setGesture)
      await tester.tap(find.byKey(const ValueKey('gesture_card_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gesture_card_2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gesture_continue')));
      await tester.pumpAndSettle();

      // onComplete called exactly once
      expect(onCompleteCallCount, equals(1));

      // Saved state assertions
      expect(find.byKey(const ValueKey('gesture_saved')), findsOneWidget);
      expect(find.byKey(const ValueKey('gesture_card_0')), findsNothing);
      expect(
        tester.widget<ElevatedButton>(find.byKey(const ValueKey('gesture_continue'))).onPressed,
        isNull,
      );

      // hasGesture() is true
      expect(await store.hasGesture(), isTrue);

      // All three storage keys are present
      final verifier = await fakeStorage.read(key: 'vault_gesture_verifier');
      final salt = await fakeStorage.read(key: 'vault_gesture_salt');
      final length = await fakeStorage.read(key: 'vault_gesture_length');

      expect(verifier, isNotNull);
      expect(verifier!.startsWith('v3:100000:'), isTrue);
      expect(salt, isNotNull);
      expect(length, equals('3'));

      // verifyGesture([1, 0, 2]) returns true (Derivation 2)
      expect(await store.verifyGesture([1, 0, 2]), isTrue);
    });
  });
}
