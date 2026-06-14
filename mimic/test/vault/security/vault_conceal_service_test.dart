// test/vault/security/vault_conceal_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/vault/security/vault_conceal_service.dart';


void main() {
  group('ShakeSensitivity Enum', () {
    test('1 · correctly maps to thresholds', () {
      expect(ShakeSensitivity.low.threshold, equals(24.0));
      expect(ShakeSensitivity.medium.threshold, equals(18.0));
      expect(ShakeSensitivity.high.threshold, equals(13.0));
    });

    test('2 · fromName resolves names or defaults to medium', () {
      expect(ShakeSensitivity.fromName('low'), equals(ShakeSensitivity.low));
      expect(ShakeSensitivity.fromName('high'), equals(ShakeSensitivity.high));
      expect(ShakeSensitivity.fromName('medium'), equals(ShakeSensitivity.medium));
      expect(ShakeSensitivity.fromName(null), equals(ShakeSensitivity.medium));
      expect(ShakeSensitivity.fromName('invalid'), equals(ShakeSensitivity.medium));
    });
  });

  group('VaultConcealService Persistence & Configuration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('3 · init() loads default medium threshold if unset', () async {
      final service = VaultConcealService(null, const PlatformServicePlaceholder());
      await service.init();
      expect(service.sensitivity, equals(ShakeSensitivity.medium));
    });

    test('4 · setSensitivity persists the choice and updates live', () async {
      final service = VaultConcealService(null, const PlatformServicePlaceholder());
      await service.init();

      await service.setSensitivity(ShakeSensitivity.high);
      expect(service.sensitivity, equals(ShakeSensitivity.high));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shake_sensitivity'), equals('high'));

      // Validate reload
      final newService = VaultConcealService(null, const PlatformServicePlaceholder());
      await newService.init();
      expect(newService.sensitivity, equals(ShakeSensitivity.high));
    });
  });
}
