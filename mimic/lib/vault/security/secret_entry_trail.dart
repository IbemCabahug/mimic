// lib/vault/security/secret_entry_trail.dart

import 'package:flutter/widgets.dart';

/// The game home, spelled out so this navigation helper stays router- and
/// Riverpod-free. It is `AppRouter.homeRoute`'s value, and `MimicGame`'s
/// constants forward to that same route table, so the two cannot drift.
const String _gameHomeRoute = '/';

/// Every vault route is registered under a '/vault-' name (AppRouter), and a
/// vault route is the one thing the decoy's exit must never land on: whoever
/// is holding the phone must not end up staring at the vault's PIN prompt.
/// This prefix is what that decision is made on.
const String _vaultRoutePrefix = '/vault-';

bool _isVaultRoute(String? name) =>
    name != null && name.startsWith(_vaultRoutePrefix);

/// Remembers which game screen the secret entry was opened from, so the
/// duress admin panel can send the mimic back to exactly that screen — the
/// live voting round when the voting-screen gesture was used, the verdict
/// screen when the results-screen sequence was used, the game home when the
/// quick-entry long-press was used — instead of tearing the whole session
/// down to '/'.
///
/// SAFETY MODEL: the trail is only ever consumed to *remove routes on top
/// of* the origin; it is never used to push anything. When there is no
/// origin on record (vault-internal lock screens, AutoLock, cold start) or
/// the origin is stale (the round moved on and the route no longer exists),
/// the exit falls through to a game route — the root of the stack when that
/// root is a game screen, and a freshly rebuilt game home otherwise. A vault
/// route can never be the landing screen, and is never pushed from here, so
/// an exit can never expose the vault.
class SecretEntryTrail {
  SecretEntryTrail._();

  static String? _originRoute;

  /// Records the route the secret entry was triggered from. Every game-side
  /// trigger must call this immediately before it pushes the PIN screen
  /// (voting-screen gesture, results-screen sequence, quick-entry
  /// long-press) — a trigger that forgets leaves the exit with no origin,
  /// and the mimic is then sent to the game home instead of the screen they
  /// actually left.
  static void setOrigin(String routeName) => _originRoute = routeName;

  /// Forgets the origin. Used by tests so the static state never leaks
  /// between cases.
  static void clear() => _originRoute = null;

  /// Returns and forgets the origin — the trail is single-use, so every
  /// exit is anchored to the entry that immediately preceded it.
  static String? consume() {
    final route = _originRoute;
    _originRoute = null;
    return route;
  }
}

/// The shared exit for the duress decoy panel: return to the recorded
/// origin route when one still exists on the stack, otherwise to a game
/// screen — never to a vault route.
///
/// - Popping (not clearing) is what preserves a live round: the route below
///   the panel is still mounted, so the voting round or the verdict screen
///   simply resumes.
/// - `route.isFirst` handles every non-game entry (AutoLock, the vault lock
///   buttons, a stale origin) by stopping at the root — the game home —
///   while removing everything above it, vault included.
/// - That stop is then CHECKED: when the walk stops on the root and the root
///   is a vault route (AutoLock and Settings → Lock Vault push '/vault-pin'
///   with pushNamedAndRemoveUntil, which makes the vault PIN route the
///   navigator's FIRST route), the walk has legally landed on the vault's
///   PIN prompt, so the root itself is replaced by the game home on a
///   cleared stack instead.
/// - When the panel IS the root (duress entered from a lock screen that
///   cleared the stack) popping is impossible, so the game home is rebuilt
///   on a cleared stack — the same replacement, still correct there.
void exitSecretScreenToOrigin(BuildContext context) {
  final navigator = Navigator.of(context);
  final origin = SecretEntryTrail.consume();
  // A vault name can never be a deliberate destination, whatever it says.
  final target = _isVaultRoute(origin) ? null : origin;

  if (!navigator.canPop()) {
    // Nothing game-side sits below (the panel replaced the only route), so
    // there is nowhere to pop back to: rebuild the game home on a cleared
    // stack. This also removes the vault PIN route the panel replaced.
    navigator.pushNamedAndRemoveUntil(_gameHomeRoute, (route) => false);
    return;
  }

  // popUntil hands the predicate each route that surfaces, so the last name
  // it is given is the route the walk stopped on.
  final seen = <String?>[];
  navigator.popUntil((route) {
    seen.add(route.settings.name);
    return (target != null && route.settings.name == target) || route.isFirst;
  });

  final landing = seen.isEmpty ? null : seen.last;
  if (_isVaultRoute(landing)) {
    // Stopped on the ROOT, and the root is a vault route: replace the root
    // itself rather than leave the mimic on the vault's PIN prompt.
    navigator.pushNamedAndRemoveUntil(_gameHomeRoute, (route) => false);
  }
}

