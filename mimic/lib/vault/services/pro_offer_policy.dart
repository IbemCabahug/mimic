/// Presentation only: never changes licenses, storage or entitlement checks.
/// Public builds hide offers by default; private staging keeps its existing UI.
const bool kProOffersVisible = bool.fromEnvironment(
  'MIMIC_PRO_OFFERS',
  defaultValue: bool.fromEnvironment('MIMIC_STAGING'),
);

/// Existing license holders keep their features; free users see no locked offers.
bool showProFeature(bool isPro) => isPro || kProOffersVisible;
