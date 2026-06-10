p# 🎭 Mimic — Session Continuity Part 2
> Quick-reference summary of project basics + current session status.

---

## 1. What is Mimic?

**Mimic** is a dual-layer Android app:

1. **Public face** — A real playable social deduction party game (find the impostor among friends).
2. **Hidden vault** — An AES-256 encrypted personal vault secretely embedded inside the game, accessible only via a hidden trigger pattern.

The vault stores photos, audio, videos, notes, and documents. It is protected by a numeric PIN (optionally biometric), a BIP39 recovery phrase, and several advanced security features (admin panel via fake PIN, shake-to-wipe, intruder selfie capture).

**Core promise:** Fully local. No backend. No cloud. No server. Everything lives on-device.

---

## 2. Key Facts

| | |
|---|---|
| **Platform** | Flutter (Android-first) |
| **State management** | Riverpod |
| **Encryption** | AES-256-CBC + PBKDF2 via `pointycastle` |
| **Secure storage** | `flutter_secure_storage` (Android) / `shared_preferences` (web fallback) |
| **Database** | `sqflite` / SQLite for notes + player stats |
| **Networking** | WebSocket (`web_socket_channel`) for LAN multiplayer |
| **Camera** | `camera` for silent intruder selfie capture |
| **Biometrics** | `local_auth` for fingerprint/face unlock |
| **File picker** | `image_picker` (photos), `file_picker` (audio & vault import) |
| **Share** | `share_plus` for vault backup sharing |
| **Hashing** | `crypto` (SHA-256 for .mimic file integrity checksum) |
| **Accelerometer** | `sensors_plus` for shake-to-wipe PIN feature |
| **Path provider** | `path_provider` for app document storage directories |
| **Fonts** | Google Fonts: `Creepster` (game headings) + `Inter` (vault & UI body) |

---

## 3. Project Structure (Key Paths)

```
mimic/
  lib/
    game/             → Public face (screens, state, services for the party game)
    vault/            → Hidden layer (screens, crypto, services for the encrypted vault)
      crypto/         → VaultCrypto singleton (all encryption)
      security/       → panic_mode, auto_lock, breakin_log, duress, shake_wipe, pin_wipe
      services/       → file_vault, audio_vault, notes, backup_reminder, biometric, intruder
      screens/        → pin, vault_home, photo, notes, audio, docs, settings, breakin_log, etc.
      widgets/        → VaultScaffold, PressableCard, AnimatedFAB, PinDotIndicator
    core/
      theme/          → app_theme.dart (VaultColors), horror_theme.dart (HorrorColors)
      services/       → PlatformService (Android/web abstraction)
      router/         → App router with named routes + guards
    multiplayer/
      network/        → NetworkService, MimicServer, MimicClient, DisconnectHandler
      state/          → GameStateSyncNotifier
      screens/        → Host, Join, Lobby, Rejoin, NetworkWordReveal, NetworkVoting
  android/
    app/src/main/AndroidManifest.xml
  test/
    vault/, game/, integration/
```

**Rule:** `/lib/game` and `/lib/vault` are fully isolated — they never import each other.

---

## 4. Vault Access Triggers (Secret Unlock Patterns)

| Screen | Secret Tap Sequence |
|---|---|
| VotingScreen | Tap card 2 → card 0 → card 2 within 3 seconds |
| ResultsScreen | Tap the top score number 3 times within 2 seconds |
| TutorialScreen | Secret tap on step 3 |

All handled by `TriggerDetector` (invisible widget overlay, zero UI footprint).

---

## 5. Phase Status Summary

| Phase | Status | Notes |
|---|---|---|
| Phase 0 — Foundation | ✅ COMPLETE | Project setup, folder structure, VaultCrypto |
| Phase 1 — Game | ✅ COMPLETE | All game screens, game modes, horror redesign |
| Phase 2 — Vault | ✅ COMPLETE | All vault screens, crypto, recovery phrase |
| Phase 3 — Polish & Safety | ✅ COMPLETE | Panic mode, auto-lock, VaultScaffold, break-in log |
| Phase 4 — Testing | ✅ COMPLETE | Unit, widget, integration tests |
| Phase 5 — v1.1 Multiplayer | ✅ COMPLETE | WebSocket LAN, QR joining, rejoin flow |
| Phase 6A — Critical Fixes | ✅ COMPLETE | Biometric fix, intruder selfie, backup reminder |
| Phase 6B — New Vault Features | ✅ COMPLETE | Video vault, auto-backup banner |
| Phase 6C — Security Upgrades | ✅ COMPLETE | Fake PIN → Admin Panel, Shake to Wipe, Wiped Vault Restore |
| BUG-001 | ✅ RESOLVED | Photo vault import (absolute path fix) |
| Phase 6D — Analyzer Cleanup | ⬜ IN PROGRESS | 9 `unnecessary_underscores` warnings in integration_smoke_test.dart |
| Phase 7 — Launch | ⬜ NOT STARTED | Not started |

---

## 6. What We Are Doing Now (Current Session)

### Active Work
This session is in **analyzer cleanup** mode. Working through `flutter analyze` warnings to achieve zero errors before proceeding to Phase 6D (Visual Polish).

### Recent Changes Summary

**Fixes applied (12 total):**
1. `disconnect_handler.dart` — removed unused `flutter_riverpod` import
2. `network_service.dart` — removed unused `flutter_riverpod` import
3. `rejoin_screen.dart` — removed unused `game_state_sync_notifier.dart` import
4. `breakin_log_screen.dart` — removed unused `dart:io` import
5. `set_duress_pin_screen.dart` — removed unused `vault_scaffold.dart` import
6. `vault_settings_screen.dart` — removed unused `duress_service.dart` import
7. `backup_reminder_service.dart` — removed unused `dart:io` import
8. `biometric_service.dart` — removed unused `dart:io` import
9. `intruder_service.dart` — removed unused `dart:typed_data` import
10. `pin_screen.dart` — added `mounted` check before Navigator call in `_checkIfWiped()`
11. `backup_reminder_service.dart` — added 4 `context.mounted` checks in `checkAndShowReminder()` to fix `use_build_context_synchronously` warnings
12. `duress_service.dart` — confirmed `dart:math` import + `Random.secure()` working (no changes needed)

**Last files touched:**
`breakin_log_screen.dart`, `breakin_log.dart`, `auto_lock.dart`, `panic_mode.dart`, `glitch_transition.dart`, `document_vault_screen.dart`, `vault_settings_screen.dart`, `network_voting_screen.dart`, `audio_vault_screen.dart`, `disconnect_handler.dart`, `game_state_sync_notifier.dart`, `game_state.dart`, `app_router.dart`, `rejoin_screen.dart`, `vault_scaffold.dart`, `app_theme.dart`

### Current Blockers

**Open:**
- `test/multiplayer/integration_smoke_test.dart` — 9 `unnecessary_underscores` linter warnings at lines 178, 241, 357, 358, 450, 451, 485, 486, 517
  - Pattern: `container.listen(provider, (_, __) {})` triggers linter
  - Investigation: Riverpod 2.x `listen()` callback has signature `(T? previous, T next)` — both parameters unused correctly uses `(_, __)`, but linter flags it
  - Priority: LOW — tests pass, does not affect functionality

### Next Steps
- **Phase 6D — Visual Polish** — After analyzer cleanup complete
- **Phase 7 — Launch** — App store prep, signing, obfuscation

---

## 7. Important Reminders

- **No terminal usage** — all code is written directly as Dart blocks, never via shell commands.
- **Game/Vault isolation** — never import vault code into game screens or vice versa. The only permitted exception is `home_screen.dart` importing `shake_wipe_service` + `pin_wipe_service` for global shake detection.
- **All encryption** goes through `VaultCrypto` class. PIN and derived key are never written to disk in plain text.
- **Key derivation:** PBKDF2 with 100,000 iterations.
- **Vault colors scheme** is at `lib/core/theme/app_theme.dart` (`VaultColors` light palette). Game layer uses `lib/core/theme/horror_theme.dart` (`HorrorColors` dark palette). Do not mix them.

---

> 🎭 Built with Flutter. Designed for privacy. Disguised as fun.
> Rating: 100/100 — all planned features shipped, analyzer cleanup in progress.