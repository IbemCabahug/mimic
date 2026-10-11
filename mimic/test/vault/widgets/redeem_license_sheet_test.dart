// test/vault/widgets/redeem_license_sheet_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/license_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/widgets/redeem_license_sheet.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> secureRead(String key) async => _storage[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.unmodifiable(_storage);

  @override
  Future<void> secureWrite(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteFile(String path) async {}

  @override
  bool isWeb() => false;

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => File(path);

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

Widget _wrapWithContainer(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  late FakePlatformService platform;
  late ProStatusService proStatus;
  late LicenseService licenseService;
  late ProviderContainer container;

  setUp(() {
    platform = FakePlatformService();
    proStatus = ProStatusService(platform, billingEnforced: true);
    licenseService = LicenseService(
      platform: platform,
      proStatus: proStatus,
      secretKey: 'test_secret_key_123',
    );

    container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(platform),
        proStatusServiceProvider.overrideWithValue(proStatus),
        licenseServiceProvider.overrideWithValue(licenseService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  testWidgets('renders Redeem Activation Code UI elements correctly', (tester) async {
    await tester.pumpWidget(_wrapWithContainer(const RedeemLicenseSheet(), container));
    await tester.pumpAndSettle();

    expect(find.text('Redeem Activation Code'), findsOneWidget);
    expect(find.text('Offline Pro Lifetime License'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Activate Pro'), findsOneWidget);
    expect(find.textContaining('Pay ₱99 with GCash'), findsOneWidget);
  });

  testWidgets('submitting empty input shows error message', (tester) async {
    await tester.pumpWidget(_wrapWithContainer(const RedeemLicenseSheet(), container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activate Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your 16-character activation code.'), findsOneWidget);
  });

  testWidgets('submitting invalid or tampered key shows error message', (tester) async {
    await tester.pumpWidget(_wrapWithContainer(const RedeemLicenseSheet(), container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'MIMIC-0000-0000-0000-0000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activate Pro'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid or unrecognized'), findsOneWidget);
    expect(await proStatus.isPro(), isFalse);
  });

  testWidgets('submitting valid key activates Pro and displays celebration', (tester) async {
    final validKey = licenseService.generateKey();

    await tester.pumpWidget(_wrapWithContainer(const RedeemLicenseSheet(), container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), validKey);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activate Pro'));
    await tester.pump(); // Start async work
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mimic Pro Activated! ⭐'), findsOneWidget);
    expect(await proStatus.isPro(), isTrue);

    // Let the auto-close timer complete
    await tester.pump(const Duration(milliseconds: 1700));
  });
}
