// test/vault/services/license_reinstall_simulation_test.dart
//
// Simulation test for the multi-device and reinstall lifecycle:
// 1. Device 1 (Phone A) activates Pro -> Allowed (1/2 slots used).
// 2. Device 2 (Tablet B) activates Pro -> Allowed (2/2 slots used).
// 3. Device 3 (Friend's phone) tries to use code -> BLOCKED (2/2 slots full).
// 4. Device 1 uninstalls Mimic (storage completely wiped).
// 5. Device 1 reinstalls and restores purchase -> ALLOWED!
//    (Hardware ID recognized, device count stays at 2/2, Pro granted).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/license_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

class FakePlatformService implements PlatformService {
  FakePlatformService({this.hardwareDeviceId});

  final String? hardwareDeviceId;
  final Map<String, String> _storage = {};

  @override
  Future<String?> secureRead(String key) async {
    if (key == kStoredLicenseDeviceId && hardwareDeviceId != null) {
      return hardwareDeviceId;
    }
    return _storage[key];
  }

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

  /// Simulates a full app uninstallation: wipes all sandboxed secure storage.
  void simulateAppUninstall() {
    _storage.clear();
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

/// Simulated cloud server (like Google Apps Script) tracking active devices per key.
class SimulatedCloudServer {
  final Map<String, List<String>> _sheetDb = {};
  static const int maxDevices = 2;

  Future<Map<String, dynamic>> handleActivationRequest(
    String url,
    Map<String, dynamic> body,
  ) async {
    final key = body['key'] as String;
    final deviceId = body['deviceId'] as String;

    final devices = _sheetDb.putIfAbsent(key, () => []);

    // 1. Device already registered? Allow immediately (reinstall on same hardware)
    if (devices.contains(deviceId)) {
      return {
        'success': true,
        'message': 'Device verified (already registered)',
        'deviceCount': devices.length,
      };
    }

    // 2. Limit check: Block if max devices reached
    if (devices.length >= maxDevices) {
      return {
        'success': false,
        'error': 'DEVICE_LIMIT_REACHED',
        'message': 'This code has already reached its limit of $maxDevices devices.',
        'deviceCount': devices.length,
      };
    }

    // 3. New device slot approved
    devices.add(deviceId);
    return {
      'success': true,
      'message': 'Device registered successfully',
      'deviceCount': devices.length,
    };
  }

  int getDeviceCount(String key) => _sheetDb[key]?.length ?? 0;
  List<String> getRegisteredDevices(String key) => List.unmodifiable(_sheetDb[key] ?? []);
}

void main() {
  test('Full Simulation: 2 devices activated -> friend blocked -> Device 1 uninstalls and restores successfully', () async {
    final server = SimulatedCloudServer();

    // Developer / Customer generates a valid license key
    final rootPlatform = FakePlatformService();
    final rootProStatus = ProStatusService(rootPlatform, billingEnforced: true);
    final keyGenerator = LicenseService(
      platform: rootPlatform,
      proStatus: rootProStatus,
      secretKey: 'test_secret_key_123',
    );
    final licenseKey = keyGenerator.generateKey();

    // -------------------------------------------------------------------------
    // STEP 1: Customer activates on Phone A (Hardware ID: android-phone-A)
    // -------------------------------------------------------------------------
    final phoneAPlatform = FakePlatformService(hardwareDeviceId: 'android-phone-A');
    final phoneAProStatus = ProStatusService(phoneAPlatform, billingEnforced: true);
    final phoneAService = LicenseService(
      platform: phoneAPlatform,
      proStatus: phoneAProStatus,
      secretKey: 'test_secret_key_123',
      activationUrl: 'https://script.google.com/macros/s/exec',
      httpPoster: server.handleActivationRequest,
    );

    expect(await phoneAProStatus.isPro(), isFalse, reason: 'Phone A starts as Free');

    final phoneAResult = await phoneAService.redeemKey(licenseKey);
    expect(phoneAResult.isSuccess, isTrue);
    expect(await phoneAProStatus.isPro(), isTrue, reason: 'Phone A unlocked Pro successfully');
    expect(server.getDeviceCount(licenseKey), equals(1), reason: 'Server records 1 active device');
    expect(server.getRegisteredDevices(licenseKey), contains('android-phone-A'));

    // -------------------------------------------------------------------------
    // STEP 2: Customer activates on Tablet B (Hardware ID: android-tablet-B)
    // -------------------------------------------------------------------------
    final tabletBPlatform = FakePlatformService(hardwareDeviceId: 'android-tablet-B');
    final tabletBProStatus = ProStatusService(tabletBPlatform, billingEnforced: true);
    final tabletBService = LicenseService(
      platform: tabletBPlatform,
      proStatus: tabletBProStatus,
      secretKey: 'test_secret_key_123',
      activationUrl: 'https://script.google.com/macros/s/exec',
      httpPoster: server.handleActivationRequest,
    );

    final tabletBResult = await tabletBService.redeemKey(licenseKey);
    expect(tabletBResult.isSuccess, isTrue);
    expect(await tabletBProStatus.isPro(), isTrue, reason: 'Tablet B unlocked Pro successfully');
    expect(server.getDeviceCount(licenseKey), equals(2), reason: 'Server now has 2/2 devices registered');
    expect(server.getRegisteredDevices(licenseKey), equals(['android-phone-A', 'android-tablet-B']));

    // -------------------------------------------------------------------------
    // STEP 3: Friend attempts to activate on Phone C (Hardware ID: android-friend-C)
    // -------------------------------------------------------------------------
    final friendPlatform = FakePlatformService(hardwareDeviceId: 'android-friend-C');
    final friendProStatus = ProStatusService(friendPlatform, billingEnforced: true);
    final friendService = LicenseService(
      platform: friendPlatform,
      proStatus: friendProStatus,
      secretKey: 'test_secret_key_123',
      activationUrl: 'https://script.google.com/macros/s/exec',
      httpPoster: server.handleActivationRequest,
    );

    final friendResult = await friendService.redeemKey(licenseKey);
    expect(friendResult.isSuccess, isFalse, reason: 'Friend must be blocked');
    expect(friendResult.errorMessage, contains('maximum device limit (2 devices)'));
    expect(await friendProStatus.isPro(), isFalse, reason: 'Friend remains on Free tier');
    expect(server.getDeviceCount(licenseKey), equals(2), reason: 'Server still has exactly 2 devices');

    // -------------------------------------------------------------------------
    // STEP 4: Customer uninstalls Mimic on Phone A
    // (Simulates complete wiping of app sandbox & secure storage)
    // -------------------------------------------------------------------------
    phoneAPlatform.simulateAppUninstall();
    expect(await phoneAProStatus.isPro(), isFalse, reason: 'Uninstalled app loses Pro cache');

    // -------------------------------------------------------------------------
    // STEP 5: Customer reinstalls Mimic on Phone A and restores purchase
    // -------------------------------------------------------------------------
    // Phone A still has the exact same physical hardware ID (android-phone-A)
    final reinstalledPhoneAService = LicenseService(
      platform: phoneAPlatform,
      proStatus: phoneAProStatus,
      secretKey: 'test_secret_key_123',
      activationUrl: 'https://script.google.com/macros/s/exec',
      httpPoster: server.handleActivationRequest,
    );

    // Customer re-enters their activation code from their email
    final restoreResult = await reinstalledPhoneAService.redeemKey(licenseKey);

    expect(restoreResult.isSuccess, isTrue, reason: 'Restore on the same device must succeed');
    expect(await phoneAProStatus.isPro(), isTrue, reason: 'Pro is restored on Phone A');
    expect(server.getDeviceCount(licenseKey), equals(2), reason: 'No extra slot was consumed! Still 2/2');
    expect(server.getRegisteredDevices(licenseKey), equals(['android-phone-A', 'android-tablet-B']));
  });
}
