# Pro paused — free-tier public release and future decision

Recorded November 11, 2026.

## Local implementation update — November 12, 2026

BUILD/COMMIT CONTINUATION: owner subsequently authorized build + commits + docs.
Version raised to 1.4.4+3013; build_release.ps1 -FreeTierOnly explicitly keeps
offers off and enforcement on without activation credentials. No install/publish
or payment configuration changes authorized. See the canonical release record:
C:/antigravity-proj/ibem-mimic/docs/mimic-docs/FREE_TIER_RELEASE_2026-11-12.md.
App dependency preservation commit ea3be93; fresh receipt tests 139 passed, wrapper
contracts 3 passed. Build output still requires actual verification before use.

Free-tier-only presentation is now implemented locally (not built/installed or
committed). Public builds default to MIMIC_PRO_OFFERS=false; private builds with
MIMIC_STAGING=true retain the existing offers UI unless explicitly overridden.
The policy is in
C:/antigravity-proj/ibem-mimic/mimic/lib/vault/services/pro_offer_policy.dart.

Settings marketing, redemption entry points, locked premium settings, paid idle
choices, media tag editors, locked search chips and paid theme/game choices are
hidden from free users. The manual no longer advertises Pro. Reached paywalls
show a neutral unavailable message without initializing billing; checkout links
are hidden and their launch handler is guarded. Direct premium-only decoy and
optimizer screens show neutral unavailability. Existing grants remain enforced
and continue exposing their existing features; licensing/storage is unchanged.

As requested afterward, no commit, release README, portfolio, deployment or
payment configuration changes are included in this UI task. Validation results
are recorded below when completed. Historical NOT-implemented statements below
describe the initial handoff and are superseded by this update.

Validation: 27 focused tests, 46 vault-screen regressions and the final targeted
settings/auto-lock rerun passed (74 successful test executions).
Source formatting check passed for all 16 affected lib files; git diff --check
passed. The final analyzer did not return a result during this task; do not claim analyzer success
or device/build validation from the test results. Logs (ignored) are at:
C:/antigravity-proj/ibem-mimic/mimic/pro_visibility_tests.log,
C:/antigravity-proj/ibem-mimic/mimic/pro_visibility_screens.log,
C:/antigravity-proj/ibem-mimic/mimic/pro_visibility_settings.log and
C:/antigravity-proj/ibem-mimic/mimic/pro_visibility_final_analyze.log.

## Owner direction

Leave payments paused. Regular Mimic users should receive the free tier only,
without Pro advertising, pricing, subscription language, purchase links, upgrade
prompts or locked-feature upsells. Keep the tested Pro implementation available
for a future decision rather than removing licensing or granting Pro to everyone.

Terminology: the current implementation sells a one-time lifetime Pro license,
not a recurring subscription. Introducing a subscription would be a new product
and implementation decision, not simply resuming the existing flow.

## Status — do not confuse policy with implementation

- Staging main path passed for one attempt through checkout, test-mode confirmation,
  simulated payment, one matching license record, email and app activation. User
  reported device count changing from 0 to 1. Evidence is screenshots/operator
  reports; restart persistence was not explicitly established.
- Restricted-production checkout changes exist locally with 516 related offline
  checks passing in the preceding implementation step. This is not a live launch.
- User reports a separate production Hello World Worker, a deployed production
  backend and backend/Worker settings prepared with new sales paused. Complete
  remote configuration/source parity has not been independently inspected.
- Live API credentials are unavailable on the individual PayMongo account shown
  by the user. Owner elected to leave payments paused rather than pursue support
  or a manual payment pilot now. No upgrade/business-registration action required
  by this handoff.
- No app UI changes have been made for the free-tier-only direction at creation
  of this document. Existing app builds may still show Pro. This document alone
  does not hide UI, disable a URL or change an installed app.
- Production checkout must remain paused. Do not connect/enable payment traffic,
  replace test credentials with live credentials or resume production provisioning
  automatically when this session is continued.

## Free-tier-only implementation scope for the next coding step

1. Introduce one explicit, default-off Pro-offer visibility policy. Keep entitlement
   enforcement separate: hiding Pro must not set BILLING_ENFORCED=false, grant
   entitlement, revoke an existing grant or erase stored activation/device data.
2. Hide the upgrade/supporter marketing cards, prices, purchase/restore marketing,
   payment links and promotional redemption entry points from the regular public
   experience. Preserve licensing internally and provide existing-license access
   only through a separately agreed non-promotional/support path if needed.
3. Hide premium-only settings, theme choices and other locked feature offers from
   free users instead of displaying PRO badges or opening a paywall. Keep free
   portions of mixed screens accessible. Already-entitled developer/test installs
   must not lose existing data or entitlement as a side effect of UI changes.
4. Handle reached premium-only routes with neutral unavailability/navigation,
   without pricing, upgrade buttons or claims that payment is coming soon. Do
   not merely make paywall calls no-ops and leave misleading clickable controls.
5. Audit all entry points, not just settings: auto-lock choices, decoy settings,
   quick entry, themes, storage optimizer, media/note menus, game screens,
   redemption checkout links and developer controls visible in distributed builds.
6. Retain the protective floor: users can access their vault and existing data,
   use free features and export/back up without paying. No data migration/deletion,
   weakened authentication, changed cryptography or endpoint switch in this slice.
7. Add focused UI tests for a free user seeing no Pro/purchase/price/badge prompts,
   premium route handling, free navigation and absence of billing/checkout calls.
   Test entitlement preservation independently. Run affected Flutter tests/analyzer;
   do not repeat the closed checkout payment cycle.
8. Build/install verification, if approved later, needs a new artifact. Do not
   claim existing installs change just because source or this document changes.

## Relevant source locations

All paths are local, not deployment destinations:

- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/screens/vault_settings_screen.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/widgets/paywall_sheet.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/widgets/redeem_license_sheet.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/screens/vault_theme_selector_screen.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/screens/storage_optimizer_screen.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/services/pro_status_service.dart
- C:/antigravity-proj/ibem-mimic/mimic/lib/vault/services/billing_service.dart

Use a fresh reference search before editing; the list is not a complete call graph.

## Decision required before resuming Pro

At a future handoff, ask the owner to select one direction:

| Decision | Consequence |
| --- | --- |
| Keep free-tier-only | Leave offers hidden and payments paused. No monetization work required. |
| Resume one-time lifetime Pro | Confirm supported live payment access, buyer scope, pricing, compatibility, recovery and deployment readiness before exposing offers. |
| Introduce recurring subscriptions | Scope a new billing/entitlement lifecycle including renewal, cancellation and expiry; current lifetime licensing is not that system. |
| Retire or redesign Pro | Separately decide feature availability and treatment of any issued licenses; do not silently revoke or erase them. |

Until an explicit decision, default to free-tier-only presentation and paused
payments. Do not interpret a passed staging test, a future available live key or
the presence of production resources as approval to expose or sell Pro.

## Resume checklist

- Read this file first and confirm whether free-tier-only UI has since been
  implemented. At this handoff it has NOT.
- Next task is the app presentation change above, not more PayMongo setup.
- Preserve staging, existing licenses, secrets, device counts and user data.
- Never include credentials, .env contents, customer records or license codes in
  this document or chat. Local .env backup is not proof of service configuration
  or secure retention; do not inspect it as part of UI work.
- Update implementation/test/build status with actual results, keeping policy,
  local code, deployed services and installed app evidence distinct.