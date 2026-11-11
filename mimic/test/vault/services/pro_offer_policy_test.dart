import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/pro_offer_policy.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

import 'pro_status_service_test.dart' show FakePlatformService;

void main() {
  test(
    'offer policy is independent from persisted license and enforcement',
    () async {
      final platform = FakePlatformService();
      final first = ProStatusService(platform, billingEnforced: true);
      expect(await first.isPro(), isFalse);
      expect(showProFeature(false), kProOffersVisible);
      await first.grantPro();
      final restarted = ProStatusService(platform, billingEnforced: true);
      expect(await restarted.isPro(), isTrue);
      expect(showProFeature(await restarted.isPro()), isTrue);
      expect(platform.store[proEntitlementKey], proEntitlementValue);
    },
  );
}
