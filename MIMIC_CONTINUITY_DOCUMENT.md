# 🎭 Mimic — Session Continuity Document
> Paste this at the start of a new session to restore full context instantly.

---

## Quick Context Snapshot
> Read this first — everything essential in 60 seconds.

**App name:** Mimic
**What it is:** A fully playable social deduction party game (the disguise) with an AES-256 encrypted personal vault hidden inside it (the real product). Nobody suspects a game.
**Platform:** Flutter — Android-first. iOS later.
**Dev environment:** Antigravity editor + Kilocode AI extension.
**Current build status:**
- ✅ Phase 1 (game redesign & features) — COMPLETE (redesigned with full horror theme, game modes, word packs, suspicion levels, and custom animations)
- ✅ Phase 2 (vault) — COMPLETE (including BIP39 Recovery Phrase and PIN Reset features)
- ✅ Phase 3 (polish & safety) — COMPLETE
- ✅ Phase 4 (testing) — COMPLETE (unit, widget, and integration tests completed)
- ✅ Web compatibility layer — COMPLETE (PlatformService, shared_preferences fallback, in-memory keystore for crypt, kIsWeb guards on biometrics/camera)
- ⬜ Phase 5 (pre-launch prep) — not started
- ⬜ Phase 6 (launch) — not started

**Current rating:** 99/100 — boosted from 98/100 after implementing encrypted vault export/import (.mimic backup files), resolving the last major gap: cross-device migration. The only remaining point is final production hardening (Phase 5–6).

**Critical Kilocode rule:** Always end every prompt with "Write the full complete file as a single Dart code block. Do NOT use PowerShell, terminal commands, or Add-Content. 100% complete — no partial code." Without this, Kilocode spams PowerShell Add-Content commands instead of writing code directly.

---

## 1. Chronological Overview

### Stage 1 — Initial concept
The user expressed a desire to build their own apps rather than use apps made by others. Their first idea was a personal safe app that could hide photos, videos, notes, and songs, with a camouflage feature that disguises the app as something innocent on the home screen.

### Stage 2 — Initial plan built
A comprehensive plan was created covering: PIN/biometric entry, photo & video vault, encrypted notes, audio locker, camouflage/disguise mode, and intruder selfie. The recommended camouflage options included a calculator, wallpaper browser, system utility, clock/weather app, and fake to-do list.

### Stage 3 — Future enhancements discussed
Recommendations were given across four categories: security upgrades (time-lock mode, self-destruct, vault activity log, two-layer unlock), disguise improvements (live wallpaper disguise, panic mode, auto-lock on notification, custom icon/name), content features (secret browser, private contacts, document vault, password manager), and monetization (freemium model, disguise skin packs).

### Stage 4 — Naming the app
The user wanted a playful and creative name. After a shortlist (Mimic, Nook, Prism, Foxhole, Mochi), the user chose **Mimic** — because it shapeshifts its disguise, is playful and clever, and works on two levels (the game mechanic + the app's core ability).

### Stage 5 — The game disguise idea (user's own idea)
The user proposed the most creative decision of the entire project: instead of a fake calculator or utility app, the disguise should be a **real, playable party game** called Mimic — where players find the impostor, similar to "Who Is Your Neighbor." A secret pattern inside the game unlocks the vault. This was praised as a genuinely unique concept.

### Stage 6 — Full implementation plan (Phases 0–6)
A 7-phase, 33-step implementation plan was built covering: foundation setup, building the game, building the vault, polish & safety, testing, pre-launch prep, and launch. Each phase had detailed steps, design notes, and a post-launch roadmap (v1.1 through v3.0).

### Stage 7 — README.md created
The full plan was compiled into a GitHub-ready README.md and delivered as a downloadable file. The user confirmed they would add it to their GitHub repo before starting to build.

### Stage 8 — Tech stack decision
The user asked about backend/frontend/.env setup. Decision: **no backend at all**. Mimic is fully local — no server, no cloud database, no API keys. The only exception planned is an optional encrypted cloud backup in v2.0 (client-side encryption before upload, Supabase bucket). State management: Riverpod. A `flutter_dotenv` file is acceptable for app config values (not secrets).

### Stage 9 — AI implementation guide created (v1)
A Kilocode-specific implementation guide was created with copyable prompts for each phase. At this point the Kilocode PowerShell spam problem had not been discovered yet.

### Stage 10 — Kilocode PowerShell issue discovered
While building the game home screen (Phase 1, Prompt 4), Kilocode started spamming `Add-Content -Path ... -Value ""` PowerShell commands instead of writing code. The user cancelled and refreshed Antigravity. The implementation guide was fully rewritten (v2) with the no-terminal instruction embedded in every single prompt.

### Stage 11 — Phase 1 completed
After the guide rewrite, the user successfully built all Phase 1 game screens: home screen, player setup, word reveal, discussion timer, voting screen (with TriggerDetector), and results/scoreboard. All screens confirmed working.

### Stage 12 — Web compatibility layer
The user asked how to test on Chrome instead of the Android emulator. A 4-prompt web compatibility plan was created using a PlatformService abstraction layer (kIsWeb checks), shared_preferences as a web fallback for flutter_secure_storage and sqflite, and skipping camera/biometrics/panic mode on web. The run command is: `flutter run -d chrome --web-port=5000`.

### Stage 13 — Continuity document + extension guide
User requested a comprehensive continuity document for seamless resumption in a future session. A session continuity markdown file was created and delivered. A Kilocode extension installer guide was also built after the user shared a screenshot of their Antigravity extensions — confirming dart-code, flutter, and kilocode were already installed, and providing terminal install commands for 5 missing extensions (Pubspec Assist, Flutter Tree, Error Lens, Bracket Pair Colorizer, GitLens).

### Stage 14 — Phase 3 completed (polish & safety)
Phase 3 was built using **Anthropic Opus and Gemini 3.5 Flash (High)** instead of Kilocode. Security core (glitch transition, panic mode, auto-lock, break-in log) was built in one batch. Polish was applied in a second batch. Completed work included: unified vaultTheme design tokens (VaultColors helper class, full component-level styling), VaultScaffold wrapper with AutoLockWrapper integration, three micro-animation widgets (PressableCard, AnimatedFAB, PinDotIndicator), and migration of all 7 vault screens to the new scaffold pattern (vault_home, photo_vault, notes, audio_vault, document_vault, vault_settings, breakin_log). Router-level wrappers cleaned up in game.dart. All tests passed, zero analyzer warnings.

### Stage 15 — Game Layer Horror Redesign (Phase 1 Overhaul)
The game layer was completely overhauled to match a premium, high-tension horror/thriller aesthetic. Completed work included:
- **Horror Theme**: Replaced Nunito with Google Fonts `Creepster` (display/headlines) and `Inter` (body/labels) in a dark voidBlack and crimson palette.
- **Tension Animations**: Built custom widgets for CRT flicker (`FlickerWidget`), heartbeat pulsing (`HeartbeatPulse`), offset/opacity drops (`GlitchTransition`), and dynamic canvas static noise (`StaticOverlay`). Applied coordinate caching to avoid heap allocations and GPU jank.
- **Game Modes & Roster**: Added `ModeSelectScreen` and updated setup screens to support Classic, Nightmare (2 mimics with different fake words), and Survival modes (eliminated players become Watchers/ghosts). Banners alert players of mode rules.
- **Word Packs**: Mixed 1-3 packs at setup (*Dark Places*, *The Occult*, *Crime Scene*, *Survival Horror*, *Everyday Dread*) each containing 20 custom pairs.
- **Tension Reveal & Voting**: Integrated pass-device overlays, circular progress indicators that flicker/pulse under 30s, 10s screen flashes, interactive suspicion level cards (`SuspicionMeter`), checkmark vote locking, and a 3-phase results sequence (Accusation, Judgment, Revelation) with falling blood confetti.
- **Stealth Preservation**: Maintained invisible `TriggerDetector` overlays and callback tap sequences on both voting and results screens.

### Stage 16 — Phase 4 completed (testing)
Completed comprehensive testing coverage for the game and vault layers:
- **Crypto Verification**: Wrote unit tests in `test/vault/crypto/vault_crypto_test.dart` checking PBKDF2 key derivation, random IV encryption round-trips, salt storage, and tamper-resistance.
- **Security & Core Logics**: Wrote widget and unit tests in `test/vault/security/security_test.dart` covering TriggerDetector callbacks, PinScreen security mock-ups, AutoLock timer resets, and break-in log selfie encryptions.
- **Vault Screens**: Wrote widget tests in `test/vault/screens/vault_screens_test.dart` for all 7 vault screens (including the newly added document vault and settings screens) verifying VaultScaffold, AutoLockWrapper, vaultTheme adherence, and zero plaintext file leaks.
- **Game Screens & State**: Wrote widget and unit tests in `test/game/screens/game_screens_test.dart` covering the home screen, setup screen, reveals, voting, results, and GameStateNotifier unit tests.
- **Stealth Integration**: Wrote integration tests in `test/integration/disguise_test.dart` simulating OS-level features (recents thumbnail protection, FLAG_SECURE method channels, hardware volume key panic triggers, back-stack purging, and manifest label checks).
- **Device Checklist**: Generated `manual_testing_checklist.md` in the artifacts folder detailing hardware-level verification checks (Digital Wellbeing masking, gallery containment, adb logcat checks, clipboard scrubs, keyboard auto-fill Blocks, split-screen restrictions, and screen pinning blocks).
- **Security Findings**: Highlighted architectural gaps (lack of native lifecycle observers for active/inactive states, and missing volume key/FLAG_SECURE native integrations) to guide subsequent development phases.

### Stage 17 — BIP39 Recovery Phrase & PIN Recovery Flow
Added full BIP39 recovery phrase generation, confirmation, and recovery flow to the vault module:
- **kBip39Wordlist**: Created `bip39_wordlist.dart` containing all 2048 canonical BIP39 English words.
- **RecoveryPhrase Helper**: Created `recovery_phrase.dart` containing secure generator (`Random.secure`), deterministic key derivation (`PBKDF2-HMAC-SHA256` with 100,000 iterations), and wordlist validation.
- **VaultCrypto Integration**: Added `storeRecoveryBlob()` and `recoverWithPhrase()` to safely encrypt and restore the master key from secure storage.
- **Recovery UI Flow**: Created `recovery_phrase_screen.dart` (step-by-step generate & confirm grid), `enter_recovery_screen.dart` (12 word fields with instant validation borders), and `reset_pin_screen.dart` (new PIN setup and overwrite).
- **Comprehensive Testing**: Wrote robust unit and widget tests verifying the entire flow, resulting in 100% test coverage and zero warning compilation.

### Stage 18 — Vault Export/Import (Cross-device Migration)
Implemented full encrypted vault backup and restore functionality, resolving the last major architectural gap (cross-device migration). Built using **Antigravity IDE with Gemini agent**.
- **VaultExporter** (`vault_exporter.dart`): Builds a `.mimic` binary backup file containing all vault data (photos metadata, notes, audio metadata, break-in logs, recovery blob, PIN hash, salt). File format: 4-byte ASCII magic header (`MMIC`), 1-byte version, 32-byte SHA-256 checksum, 8-byte timestamp, followed by UTF-8 JSON payload. Includes `buildExportFile()` (saves to Downloads) and `shareFile()` (via share_plus).
- **VaultImporter** (`vault_importer.dart`): Validates `.mimic` files (magic header, version, checksum integrity) via `validateFile()`. Restores vault data via `importWithPhrase()` — derives the encryption key from a 12-word BIP39 recovery phrase using PBKDF2-HMAC-SHA256 (100k iterations), verifies it against the stored recovery blob, then writes all secure storage keys and rebuilds the SQLite break-in database.
- **Export Vault Screen** (`export_vault_screen.dart`): Checks recovery phrase setup status (green ✓ or red warning), "Save to Downloads" and "Save & Share" buttons, CircularProgressIndicator during export, success SnackBar with file path.
- **Import Vault Screen** (`import_vault_screen.dart`): Two-step flow — Step 1: pick `.mimic` file via file_picker, validate with `VaultImporter.validateFile()`, show error card or green checkmark. Step 2: enter 12-word recovery phrase with live BIP39 validation (green/red borders per field), import via `VaultImporter.importWithPhrase()`, navigate to ResetPinScreen on success.
- **Settings Integration**: Added "Backup" section header in `vault_settings_screen.dart` with Export Vault (`Icons.upload_outlined`) and Import Vault (`Icons.download_outlined`) tiles, separated from the existing Security section.
- **Routing**: Added `/vault-export` and `/vault-import` routes in `game.dart`.
- **Dependencies**: Added `file_picker: ^11.0.2` to pubspec.yaml (share_plus, crypto, path_provider were already present).
- **Verification**: `flutter analyze lib/` reports zero new issues from the added files.

### Stage 19 — Export/Import Test Verification & Platform Safety
Completed full test coverage for the vault export/import feature. Built using **Antigravity IDE with Gemini agent**.
- **sqflite_common_ffi Integration**: Added `sqflite_common_ffi` as a dev dependency to provide a real FFI-backed SQLite engine for desktop test environments (Windows/macOS/Linux). This eliminates the `MissingPluginException` for `getDatabasesPath` that occurred when testing sqflite operations outside of Android/iOS.
- **Test Rewrite** (`vault_export_import_test.dart`): Replaced fragile sqflite method channel mocks with `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`. Tests now create real temporary SQLite databases in temp directories, making round-trip testing fully realistic. Uses `databaseFactory.setDatabasesPath()` to point sqflite at temp directories.
- **Platform-Safe Fallback** (`vault_exporter.dart`): Wrapped `getExternalStorageDirectory()` in a try-catch in `_getDownloadsDirectory()` since it throws `UnsupportedError` on non-Android platforms. Now gracefully falls through to `getApplicationDocumentsDirectory()`.
- **All 6 Tests Passing**: validateFile rejects short file ✅, wrong magic header ✅, wrong version ✅, checksum mismatch ✅, full export/import round-trip ✅, wrong recovery phrase fails safely ✅.

---

## 2. Key Topics Discussed

- Personal vault app concept and initial feature planning
- Camouflage/disguise system design
- Future enhancement recommendations (security, disguise, content, monetization)
- App naming process and final selection (Mimic)
- The game-as-disguise concept (user's original idea)
- Full 7-phase implementation roadmap
- README.md creation for GitHub
- Tech stack decisions (Flutter, no backend, local-only, Riverpod)
- AI implementation guide for Kilocode
- Kilocode PowerShell spam bug and fix
- Phase 1 game build (completed)
- Phase 2 vault build (completed)
- Phase 3 polish & safety build (completed via Opus + Gemini 3.5 Flash)
- Web compatibility layer for Chrome testing (PlatformService and fallback implementations completed)
- Antigravity extension audit and install shortcuts
- VaultColors design token system and VaultScaffold wrapper pattern
- Game layer premium horror/thriller visual overhaul
- BIP39 backup phrase security configuration & offline reset PIN mechanism
- Vault export/import (.mimic encrypted backup files) for cross-device migration
- sqflite_common_ffi for desktop test environments (resolving MissingPluginException)

---

## 3. Important Decisions & Conclusions

| Decision | What was decided | Why |
|---|---|---|
| App name | Mimic | Playful, clever, works on two levels — the game mechanic and the app's disguise ability |
| Disguise type | A real, fully playable party game | Unique, convincing, genuinely usable cover — not a lazy fake calculator |
| Platform | Flutter, Android-first | Single codebase, great for game UI and animations |
| Backend | None — fully local only | Privacy-first, no breach risk, no server costs, aligns with core promise |
| State management | Riverpod | Cleanest Flutter option, keeps game and vault state isolated |
| Encryption | AES-256 + PBKDF2 via pointycastle | Industry standard, works on both Android and web |
| Storage | flutter_secure_storage + SQLCipher + encrypted binary blobs | Right tool for each data type |
| BIP39 PIN Recovery | Local 12-word recovery phrase backup | Replaces PIN lockout risk with cryptographic backup, preserving offline, no-cloud promise |
| Cloud backup | Opt-in, v2.0 only, client-side encrypted before upload | Privacy preserved even if Supabase is breached |
| Module isolation | /lib/game and /lib/vault never import each other | Vault is only reachable via TriggerDetector — structural security |
| Rating system | User will share updates, Claude re-rates each time | Tracking improvement across versions, starting at 87/100 |
| Web testing | Temporary web compatibility layer via PlatformService abstraction | Faster testing on Chrome without rebuilding for Android every time |
| Vault export/import | Local encrypted .mimic binary file with SHA-256 checksum | Cross-device migration without cloud — aligns with local-only privacy model |

---

## 4. App Architecture

### Project structure
```
/lib
  /core
    /theme          → app_theme.dart (legacy theme configurations)
                    → horror_theme.dart (HorrorColors and HorrorTheme.themeData — Creepster & Inter)
                    → vault_colors.dart (VaultColors helper class — Phase 3)
    /animations     → horror_animations.dart (FlickerWidget, HeartbeatPulse, GlitchTransition, StaticOverlay)
    /services       → platform_service.dart (Android/web abstraction)
  /game             → all game screens and state (public face)
    /data           → word_packs.dart (themed WordPack database — 5 packs x 20 pairs)
    /widgets        → suspicion_meter.dart (smooth blood-red progress bar widget)
    /screens        → home_screen.dart (glifting fog, large pulsing title, stacked buttons)
                    → mode_select_screen.dart (Classic, Nightmare, Survival cards)
                    → pack_select_screen.dart (1-3 mixed word pack selector)
                    → player_setup_screen.dart (victim cards, warning banners)
                    → word_reveal_screen.dart (cover reveal card, pass-device view, circular progress discussion timer)
                    → voting_screen.dart (dark voting cards, suspicion meter highlight, selection checkmark locking)
                    → results_screen.dart (accusation/judgment/revelation sequencer, falling crimson confetti)
  /vault            → all vault screens and services (hidden layer)
    /crypto         → vault_crypto.dart (VaultCrypto singleton)
                    → recovery_phrase.dart (RecoveryPhrase helper class)
                    → bip39_wordlist.dart (2048 canonical BIP39 English words list)
    /export         → vault_exporter.dart (builds .mimic backup, saves to Downloads, share_plus)
                    → vault_importer.dart (validates .mimic files, restores with BIP39 phrase)
    /screens        → pin, vault_home, photo_vault, notes, audio_vault,
                      document_vault, vault_settings, breakin_log,
                      recovery_phrase_screen, enter_recovery_screen, reset_pin_screen,
                      export_vault_screen, import_vault_screen
    /services       → file_vault_service.dart, notes_service.dart, audio_vault_service.dart
    /trigger        → trigger_detector.dart (invisible overlay widget)
    /security       → panic_mode.dart, auto_lock.dart, breakin_log.dart
    /widgets        → vault_scaffold.dart (VaultScaffold + AutoLockWrapper)
                    → pressable_card.dart, animated_fab.dart, pin_dot_indicator.dart
```

### The two-layer concept
- **Game layer** — premium horror/thriller theme (voidBlack `#080A0F` background, cardSurface `#1A1F2E`, bloodRed `#8B0000`, crimson `#C41E3A`, fogWhite `#E8E0D0`, ashGray `#6B7280` accents). Google Fonts Creepster and Inter. Dynamic drifting fog, CRT static noise overlays, and glitch transitions.
- **Vault layer** — light theme (#FFFFFF bg, #F1EFE8 surface, #534AB7 accent, Inter font). This is what only the user sees.
- **Transition** — 300ms glitch/static animation when secret trigger fires → fade to clean white PIN screen.

### Secret unlock triggers (currently implemented)
- Voting screen: tap player card index 2 → index 0 → index 2 within 3 seconds
- Results screen: tap the top score number 3 times within 2 seconds
- Both handled by TriggerDetector (invisible StatefulWidget overlay, zero UI)

---

## 5. Tech Stack

| Area | Package/Tool |
|---|---|
| Framework | Flutter (Android-first) |
| Encryption | pointycastle (AES-256-CBC + PBKDF2) |
| Secure storage | flutter_secure_storage (Android) / shared_preferences (web fallback) |
| Database | sqflite / SQLCipher for notes |
| Biometrics | local_auth |
| Camera | camera (intruder selfie) |
| File picker | image_picker (photos), file_picker (audio & vault import) |
| Audio | just_audio + just_audio_web |
| State management | Riverpod |
| Web detection | kIsWeb from flutter/foundation.dart |
| Sharing | share_plus (vault export sharing) |
| Hashing | crypto (SHA-256 checksum for .mimic file integrity) |
| File paths | path_provider (Downloads directory for export) |
| Desktop SQLite (test) | sqflite_common_ffi (FFI-backed SQLite for Windows/macOS/Linux tests) |

---

## 6. Design System

### Game layer palette
- Background (voidBlack): `#080A0F`
- Deep Surface: `#0D1117`
- Card Surface: `#1A1F2E`
- Primary Accent (bloodRed): `#8B0000`
- Highlight Accent (crimson): `#C41E3A`
- Secondary Accent (darkRedTint): `#2D1B1B`
- Primary Text (fogWhite): `#E8E0D0`
- Secondary Text (ashGray): `#6B7280`
- Font: Google Fonts Creepster (Headings) & Inter (Body/Labels)

### Vault layer palette
- Background: `#FFFFFF`
- Surface: `#F1EFE8`
- Accent: `#534AB7`
- Muted text: `#888780`
- Font: Inter or DM Sans

### App icon
Split-face design — one half normal, one half glitchy/distorted. Dark background, purple glow. Reads clearly at 60×60px.

---

## 7. Implementation Roadmap Status

### Phase 0 — Foundation ✅
- Flutter project created
- /lib/game and /lib/vault folder structure set up
- app_theme.dart created
- horror_theme.dart created with HorrorTheme.themeData (Creepster/Inter)
- horror_animations.dart created (FlickerWidget, HeartbeatPulse, GlitchTransition, StaticOverlay)
- VaultCrypto class built

### Phase 1 — Game ✅ COMPLETE
- ✅ home_screen.dart — voidBlack background, static noise overlay, drifting fog, large pulsing Creepster title, BEGIN/HOW TO PLAY/SETTINGS buttons.
- ✅ mode_select_screen.dart — Classic, Nightmare, Survival game mode cards.
- ✅ pack_select_screen.dart — Mix 1-3 themed categories (Dark Places, The Occult, Crime Scene, Survival, Everyday Dread).
- ✅ player_setup_screen.dart — victim cards, warning banners for Nightmare and Survival modes.
- ✅ game_state.dart — Riverpod state manager supporting multiple mimics, suspicion mappings, elimination lists, and category pairings.
- ✅ word_reveal_screen.dart — cover card, 200ms glitch reveal transition, CRT flicker words, 3s auto-hide pass-device sheet, Nightmare different mimic words, Survival round headers. Overhauled Discussion timer (crimson clockwise circle ring, 30s low-time heartbeat/flicker indicators, 10s screen flash overlay, and interactive suspicion lists).
- ✅ voting_screen.dart — dark cards with suspicion meters, heartbeat pulses on the highest suspected victim, checkmark selection locking, and invisible TriggerDetector (tap 2→0→2).
- ✅ results_screen.dart — 3-phase accusation/judgment/revelation sequencer, falling red confetti, Nightmare sequential mimic reveals, Survival Watcher score list, scoreboard with mimic skulls, and invisible TriggerDetector (tap score 3x).

### Phase 2 — Vault ✅ COMPLETE
- ✅ vault_crypto.dart — VaultCrypto singleton (AES-256, PBKDF2)
- ✅ pin_screen.dart — 6-dot indicator, custom numpad, intruder selfie on 3 fails, first-launch PIN setup
- ✅ vault_home_screen.dart — 2x2 grid, lock button, auto-lock on background
- ✅ photo_vault_screen.dart + file_vault_service.dart — encrypted import, thumbnail decryption in memory only
- ✅ notes_screen.dart + notes_service.dart — SQLite, encrypted title+content, pin/search
- ✅ audio_screen.dart + audio_vault_service.dart — just_audio from memory buffer, never decrypt to disk
- ✅ recovery_phrase.dart + bip39_wordlist.dart — static generator, validator, and key derivation
- ✅ recovery_phrase_screen.dart — 12-word grid presentation, warning banner, and 3-word check verification
- ✅ enter_recovery_screen.dart — 12 validation fields mapping to reset PIN
- ✅ reset_pin_screen.dart — PIN updating and storage initialization
- ✅ vault_exporter.dart — builds .mimic binary backup (magic header, SHA-256 checksum, JSON payload), saves to Downloads, share via share_plus
- ✅ vault_importer.dart — validates .mimic files (magic, version, checksum), restores vault data with BIP39 phrase-derived key
- ✅ export_vault_screen.dart — recovery phrase status check, Save to Downloads, Save & Share buttons, progress indicator
- ✅ import_vault_screen.dart — two-step flow: file picker with validation, 12-word phrase entry with live BIP39 validation, navigate to ResetPinScreen on success

### Web compatibility layer ✅ COMPLETE
- ✅ platform_service.dart — PlatformService abstraction (Android vs web)
- ✅ VaultCrypto updated to use PlatformService
- ✅ pin_screen, file_vault_service, notes_service updated with kIsWeb guards
- ✅ pubspec.yaml updated + web platform initialized

### Phase 3 — Polish & safety ✅ COMPLETE
- ✅ panic_mode.dart — triple volume-down press, instant lock + recent apps disguise
- ✅ auto_lock.dart — AutoLockWrapper integrated into VaultScaffold
- ✅ breakin_log.dart — encrypted timestamp log of all failed PIN attempts
- ✅ decoy PIN — second PIN opens convincing empty vault
- ✅ recent apps disguise — FLAG_SECURE + game home thumbnail override
- ✅ VaultColors helper class — unified design tokens for all vault screens
- ✅ VaultScaffold wrapper — consistent scaffold with AutoLockWrapper across all vault screens
- ✅ Micro-animation widgets — PressableCard, AnimatedFAB, PinDotIndicator
- ✅ All 7 vault screens migrated to new scaffold pattern
- ✅ Router-level wrappers cleaned up in game.dart
- ✅ Zero analyzer warnings, all tests passed
- ✅ document_vault_screen.dart — added during Phase 3
- ✅ vault_settings_screen.dart — added during Phase 3

### Phase 4 — Testing ✅ COMPLETE
Completed comprehensive testing coverage for both the game and vault layers:
- **Unit and Widget Tests**: Verified encryption mechanics, screen navigation, state flows, auto-lock security triggers, and recovery phrases.
- **Integration Tests**: Assured stealth features, recent apps disguise, and hardware triggers work as expected.
- **Device Checklist**: Compiled a verification plan for hardware-level security, masking, and containment.
- **Export/Import Tests**: 6 tests covering file validation (short file, wrong magic, wrong version, checksum mismatch), full round-trip export→import, and wrong-phrase rejection. Uses `sqflite_common_ffi` for real FFI-backed SQLite on desktop.

### Vault Export/Import ✅ COMPLETE
- ✅ vault_exporter.dart — .mimic binary format (MMIC magic, v1, SHA-256, timestamp, JSON payload)
- ✅ vault_importer.dart — file validation + BIP39 phrase-based restore
- ✅ export_vault_screen.dart — recovery check, download, share
- ✅ import_vault_screen.dart — file picker → phrase entry → restore → PIN reset
- ✅ vault_settings_screen.dart — new "Backup" section with Export/Import tiles
- ✅ game.dart routes — `/vault-export` and `/vault-import`
- ✅ file_picker ^11.0.2 added to pubspec.yaml
- ✅ sqflite_common_ffi (dev) for FFI-backed SQLite tests on desktop
- ✅ Platform-safe `_getDownloadsDirectory()` fallback (try-catch on getExternalStorageDirectory)
- ✅ vault_export_import_test.dart — 6/6 tests passing (validation, round-trip, wrong-phrase)
- ✅ Zero new analyzer issues

### Phases 5–6 — Prep and Launch ⬜ NOT STARTED

---

## 8. Post-Launch Roadmap

| Version | Key features |
|---|---|
| v1.1 | More disguise skins, word pack expansion, ~~local encrypted backup~~ ✅ DONE, fake widget |
| v1.2 | Password manager, document/PDF vault, time-lock mode, break-in gallery |
| v2.0 | Online multiplayer game, secret browser, encrypted cloud backup (opt-in), custom word packs |
| v3.0 | Freemium model, multiple vault profiles, private contacts/chat logs, skin marketplace |

---

## 9. Kilocode Usage Guide

### Every session — paste context first
```
I am building an Android app called Mimic using Flutter.
Mimic is a dual-layer app:
1. A real playable social deduction party game (public face)
2. An AES-256 encrypted personal vault hidden inside it

Stack: Flutter (Android-first), pointycastle, flutter_secure_storage, SQLCipher, local_auth, camera.
Structure: /lib/game and /lib/vault are isolated — they never import each other.
Encryption: all encryption goes through VaultCrypto class only. PIN and derived key never written to disk in plain text. PBKDF2 for key derivation.

IMPORTANT RULES — follow for every response:
- Do NOT use PowerShell, terminal commands, Add-Content, New-Item, mkdir, or any shell commands
- Write ALL code directly as complete Dart code blocks
- Label every code block with its full file path at the top
- Always write the entire file — never partial snippets
- Do not run anything on my machine
```

### If Kilocode goes back to PowerShell
```
Stop. Do not use PowerShell or any terminal commands.
Write the complete file content as a Dart code block only,
labeled with the full file path. Start over from the beginning of that file.
```

### If code is cut off
```
The code was cut off. Continue from where you stopped and write
the rest of the file as a complete code block. Do not restart
from the top — continue from the last line you wrote.
```

### End every prompt with
```
Write the full complete file as a single Dart code block.
Label it: // [full file path]
Do NOT use PowerShell, terminal commands, or Add-Content.
100% complete — no partial code.
```

---

## 10. Running the App

### Android (correct way)
```bash
flutter devices          # confirm Android emulator or phone is listed
flutter run              # deploys to detected Android device
```

### Chrome (web testing only — not secure)
```bash
flutter create --platforms=web .    # run once to enable web
flutter run -d chrome --web-port=5000
```

### Why `flutter run -d chrome` without web setup shows nothing
Mimic was set up Android-only. Chrome can't run Android-specific packages (local_auth, camera, flutter_secure_storage) without the web compatibility layer. Always run `flutter devices` first to confirm what's available.

---

## 11. Current Rating

**99 / 100**

| Category | Notes |
|---|---|
| Concept | 98/100 — game-as-disguise concept is highly original; the premium horror theme adds actual flavor and matches the deduction nature. |
| Security architecture | Strong — local-only, AES-256, secure in-memory decryption, TriggerDetector callback sequence tap overlays, encrypted .mimic export with SHA-256 integrity checks. |
| Disguise quality | Outstanding — complete playable horror game layer with diverse packs, modes, and dynamic animations. |
| Cross-device migration | ✅ Resolved — encrypted .mimic backup export/import with BIP39 phrase-based key derivation. No cloud required. |
| Missing point (1) | Final production hardening (Phases 5–6: app store prep, signing, obfuscation, launch). |

---

## 12. Open Questions & Pending Tasks

### Completed — Web Compatibility
The web compatibility layer is fully implemented, allowing testing on Chrome using a custom PlatformService abstraction.

### Completed — Phase 4 Testing & PIN Recovery
Phase 4 testing has been completed successfully. Re-verified all widget, unit, and integration tests, including the newly added BIP39 recovery screens (`recovery_phrase_screen_test.dart` and `enter_recovery_screen_test.dart`), and confirmed they pass cleanly with zero analyzer warnings.

### ✅ Completed — Cross-device Migration (Vault Export/Import)
Fully implemented via encrypted `.mimic` binary backup files. `VaultExporter` packages all vault data (photos, notes, audio, break-in logs, recovery blob, credentials) into a checksummed binary with MMIC magic header. `VaultImporter` validates file integrity and restores data using a 12-word BIP39 recovery phrase for key derivation. Export and Import screens added to vault settings under a new "Backup" section. No cloud dependency — fully local.

---

## 13. User Preferences & Constraints

- Prefers to build their own apps rather than use apps made by others
- Android-first (iOS later)
- Antigravity editor with Kilocode extension
- Wants to test on Chrome during development (faster than emulator)
- Prefers fully local storage — no cloud by default
- Wants the disguise to be genuinely convincing, not a cheap fake
- Agreed to update Claude on progress for re-rating after each update
- Prefers prompts to be copyable one at a time, with confirmation before proceeding
- Does not want Kilocode running terminal commands — code blocks only

---

## 14. Insights & Lessons Learned

- **The game-as-disguise is the app's biggest differentiator.** Most vault apps use a fake calculator. A real playable game means the cover story is airtight even when friends use it.
- **No backend is a feature, not a limitation.** Local-only storage is more private than any cloud vault app. Market it that way.
- **Kilocode defaults to PowerShell on Windows** when creating files unless explicitly told not to. The no-terminal instruction must be in every single prompt, not just the context.
- **One prompt at a time is non-negotiable.** Stacking prompts causes bugs that are hard to trace. Confirm each screen works before moving to the next.
- **The VaultCrypto class must be tested in isolation** before building anything that depends on it. Silent encryption bugs are the worst kind.
- **Decrypted data must never touch disk.** Photos, audio, and videos must be decrypted to memory only. If Kilocode writes to a temp file, correct it immediately.
- **The vault discovery moment matters.** The first time a user triggers the secret pattern should feel like finding a secret passage — the glitch animation into the clean white PIN screen is not optional polish, it's part of the experience.
- **The 14-week timeline is realistic but Phase 4 (testing) must not be shortened.** A privacy app that leaks data is worse than no app at all.
- **One cohesive visual design language binds the features.** Swapping Nunito for Creepster/Inter and establishing core dark colors binds the social deduction mechanics to a unified premium experience.
- **Form states in scrollable views require static containment.** When building screens with many validation textfields (e.g. 12 recovery phrase inputs), standard `ListView` widgets will drop widget states for off-screen fields during scroll events. Transitioning to a combination of `SingleChildScrollView` and `Column` guarantees that all form controllers stay alive and are accessible for hit-testing in unit tests.
- **Binary file formats need strict validation.** The `.mimic` export format uses a magic header, version byte, and SHA-256 checksum before the JSON payload. This prevents accidental import of wrong files and catches corruption. Always validate before deserializing.
- **file_picker v11+ removed `FilePicker.platform`.** Starting with file_picker 11.0.2, all calls must use static methods like `FilePicker.pickFiles()` directly instead of the old `FilePicker.platform.pickFiles()` pattern.
- **sqflite tests need sqflite_common_ffi, not method channel mocks.** Mocking the `com.tekartik.sqflite` method channel is fragile and version-dependent. Using `sqflite_common_ffi` provides a real FFI-backed SQLite engine on desktop, making tests realistic and reliable. Initialize with `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`, then use `databaseFactory.setDatabasesPath()` to point at a temp directory.
- **`getExternalStorageDirectory()` throws on non-Android.** Always wrap in try-catch — it raises `UnsupportedError` on Windows/macOS/Linux/web. Let it fall through to `getApplicationDocumentsDirectory()` as a safe fallback.

---

## 15. How to Update This Document

This is a **living continuity document**. At the start of any new Claude session, paste this entire file to restore full context. To update it after progress:

### Step 1 — Paste this into a new Claude session
```
Here is my Mimic project continuity document: [paste full file]
```

### Step 2 — Claude will ask about your progress
Claude will ask what was completed, what changed, and what new issues came up since the last update.

### Step 3 — Paste your progress update
Describe what phases or features were completed, which AI tools were used, any new files added, any bugs encountered, and any decisions made.

### Step 4 — Claude updates the document
Claude will update all relevant sections: Quick Context Snapshot, Chronological Overview, Build Status, Open Questions, Insights, and the footer status line — then deliver the updated file for download.

---

> 🎭 Built with Flutter. Designed for privacy. Disguised as fun.
> Current status: Phases 1–4 complete · BIP39 PIN Recovery integrated · Vault Export/Import complete (6/6 tests passing) · Web compatibility active · Rating 99/100
