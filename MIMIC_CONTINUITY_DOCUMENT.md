# 🎭 Mimic — Session Continuity Document
> Paste this at the start of a new session to restore full context instantly.

---

## Quick Context Snapshot
> Read this first — everything essential in 60 seconds.

**App name:** Mimic
**What it is:** A fully playable social deduction party game (the disguise) with an AES-256 encrypted personal vault hidden inside it (the real product). Nobody suspects a game.
**Platform:** Flutter — Android-first. iOS later.
**Dev environment:** Antigravity editor + Gemini Flash 2.5 (code writing). Claude used for final feature review and testing phases only.
**Current build status:**
- ✅ Phase 1 (game redesign & features) — COMPLETE (redesigned with full horror theme, game modes, word packs, suspicion levels, and custom animations)
- ✅ Phase 2 (vault) — COMPLETE (including BIP39 Recovery Phrase and PIN Reset features)
- ✅ Phase 3 (polish & safety) — COMPLETE
- ✅ Phase 4 (testing) — COMPLETE (unit, widget, and integration tests completed)
- ✅ Web compatibility layer — COMPLETE (PlatformService, shared_preferences fallback, in-memory keystore for crypto, kIsWeb guards on biometrics/camera)
- ✅ BIP39 PIN Recovery — COMPLETE
- ✅ Vault Export/Import (.mimic backup files) — COMPLETE
- 🔄 Phase 5 (v1.1 — Multiplayer + Engagement) — IN PLANNING
- ⬜ Phase 6 (pre-launch prep) — not started
- ⬜ Phase 7 (launch) — not started

**Current rating:** 99/100 — the only remaining point is final production hardening (Phases 6–7). v1.1 multiplayer + engagement features will push this to 100/100 on completion.

**AI workflow:**
- **Gemini Flash 2.5** — writes all code (one file at a time)
- **Claude** — final review and testing phase only (not per-file review)
- No Kilocode terminal rule needed for Gemini — it writes clean code blocks directly

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
- **Device Checklist**: Generated `manual_testing_checklist.md` in the artifacts folder detailing hardware-level verification checks (Digital Wellbeing masking, gallery containment, adb logcat checks, clipboard scrubs, keyboard auto-fill blocks, split-screen restrictions, and screen pinning blocks).

### Stage 17 — BIP39 Recovery Phrase & PIN Recovery Flow
Added full BIP39 recovery phrase generation, confirmation, and recovery flow to the vault module:
- **kBip39Wordlist**: Created `bip39_wordlist.dart` containing all 2048 canonical BIP39 English words.
- **RecoveryPhrase Helper**: Created `recovery_phrase.dart` containing secure generator (`Random.secure`), deterministic key derivation (`PBKDF2-HMAC-SHA256` with 100,000 iterations), and wordlist validation.
- **VaultCrypto Integration**: Added `storeRecoveryBlob()` and `recoverWithPhrase()` to safely encrypt and restore the master key from secure storage.
- **Recovery UI Flow**: Created `recovery_phrase_screen.dart` (step-by-step generate & confirm grid), `enter_recovery_screen.dart` (12 word fields with instant validation borders), and `reset_pin_screen.dart` (new PIN setup and overwrite).
- **Comprehensive Testing**: Wrote robust unit and widget tests verifying the entire flow, resulting in 100% test coverage and zero warning compilation.

### Stage 18 — Vault Export/Import (Cross-device Migration)
Implemented full encrypted vault backup and restore functionality, resolving the last major architectural gap (cross-device migration). Built using **Antigravity IDE with Gemini agent**.
- **VaultExporter** (`vault_exporter.dart`): Builds a `.mimic` binary backup file containing all vault data. File format: 4-byte ASCII magic header (`MMIC`), 1-byte version, 32-byte SHA-256 checksum, 8-byte timestamp, followed by UTF-8 JSON payload. Includes `buildExportFile()` (saves to Downloads) and `shareFile()` (via share_plus).
- **VaultImporter** (`vault_importer.dart`): Validates `.mimic` files (magic header, version, checksum integrity). Restores vault data via `importWithPhrase()` — derives the encryption key from a 12-word BIP39 recovery phrase using PBKDF2-HMAC-SHA256 (100k iterations).
- **Export/Import Screens**: Two-step import flow (file picker → phrase entry → restore → PIN reset). Export screen checks recovery phrase status, offers Save to Downloads and Save & Share.
- **Settings Integration**: Added "Backup" section in `vault_settings_screen.dart` with Export/Import tiles.
- **All 6 Tests Passing**: validateFile rejects short file, wrong magic, wrong version, checksum mismatch, full round-trip, wrong-phrase rejection.

### Stage 19 — Export/Import Test Verification & Platform Safety
- `sqflite_common_ffi` integrated for real FFI-backed SQLite in desktop test environments.
- `_getDownloadsDirectory()` wrapped in try-catch for non-Android platform safety.
- Zero new analyzer issues. All 6 tests passing.

### Stage 20 — v1.1 Feature Planning (Multiplayer + Engagement)
Major game enhancement plan designed to make Mimic a genuinely convincing published game and push rating to 100/100. Three areas scoped:

**Multiplayer:**
- Local WiFi multiplayer via `nearby_connections` (v1.1)
- Online multiplayer deferred to v2.0
- Host/Guest model — one device hosts, others join via room code
- Max 2–10 players

**Communication (Voice + Chat):**
- Push-to-talk voice via `flutter_webrtc` — hold button to speak
- Text chat overlay — available simultaneously with voice
- Each player independently chooses their preferred mode
- Both auto-disabled during word reveal, voting, and results phases
- Pulsing red speaking indicator next to active speaker's name

**Engagement Features:**
- Player profiles with persistent stats and horror avatars
- Suspicion Score system (cumulative points for all actions)
- Rank tiers: Bystander → Suspect → Investigator → Phantom → The Original
- Local leaderboard (online leaderboard deferred to v2.0)
- Post-round Case File screen (shareable dramatic summary)
- Auto-generated Roast Cards (one-liner humor based on round events)
- Special roles in Nightmare mode: Informant, Paranoid, Ally
- Accusation phase before voting
- Voting pressure timer (15s per player)
- Horror ambience audio during discussion phase (optional toggle)
- Custom room rules (host-configurable text rules shown pre-round)

**Solo Tutorial Mode:**
- 5-step fake how-to-play walkthrough
- Step 3 secretly embeds the TriggerDetector vault trigger
- If triggered → glitch transition → PIN screen
- If completed normally → "You're ready to play!" screen — 100% innocent

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
- AI workflow switch: Gemini Flash 2.5 for code, Claude for final review/testing only
- v1.1 multiplayer + voice/chat + engagement features planning

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
| Multiplayer networking | nearby_connections for local WiFi (v1.1), online deferred to v2.0 | Keeps local-only promise for v1, scales naturally to v2 |
| Voice communication | Push-to-talk via flutter_webrtc | Cleaner than open mic — no accidental broadcasting |
| Voice + chat | Both available simultaneously, player chooses | Maximum flexibility without forcing one mode on all players |
| Leaderboard | Local only (v1.1), online deferred to v2.0 | Consistent with local-only architecture |
| AI workflow | Gemini Flash 2.5 for code, Claude for final review/testing | Faster iteration — Claude reserved for quality gate moments |

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
    /models         → player_profile.dart (profile data model + Suspicion Score logic)
                    → special_roles.dart (Informant, Paranoid, Ally role definitions)
    /multiplayer    → nearby_service.dart (WiFi P2P wrapper)
                    → game_sync.dart (game state serialization)
                    → voice_service.dart (WebRTC push-to-talk)
                    → chat_service.dart (text message relay)
    /services       → stats_service.dart (read/write player stats to SQLite)
                    → ambience_service.dart (horror background audio)
    /widgets        → suspicion_meter.dart (smooth blood-red progress bar widget)
                    → roast_card.dart (auto-generated post-round one-liners)
                    → push_to_talk_button.dart (hold-to-speak button)
                    → chat_overlay.dart (sliding chat panel)
                    → speaking_indicator.dart (pulsing red dot)
    /screens        → home_screen.dart
                    → mode_select_screen.dart (Classic, Nightmare, Survival)
                    → pack_select_screen.dart
                    → player_setup_screen.dart
                    → word_reveal_screen.dart
                    → voting_screen.dart (TriggerDetector: tap 2→0→2)
                    → results_screen.dart (TriggerDetector: tap score 3x)
                    → multiplayer_menu_screen.dart (Host vs Join)
                    → host_lobby_screen.dart (room code + player list)
                    → join_lobby_screen.dart (room code entry + waiting room)
                    → tutorial_screen.dart (solo tutorial + hidden vault trigger step 3)
                    → player_profile_screen.dart (stats, title, avatar)
                    → case_file_screen.dart (post-round dramatic summary)
                    → leaderboard_screen.dart (local ranked leaderboard)
  /vault            → all vault screens and services (hidden layer)
    /crypto         → vault_crypto.dart (VaultCrypto singleton)
                    → recovery_phrase.dart (RecoveryPhrase helper class)
                    → bip39_wordlist.dart (2048 canonical BIP39 English words list)
    /export         → vault_exporter.dart (builds .mimic backup)
                    → vault_importer.dart (validates + restores .mimic files)
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
- Tutorial screen (v1.1): secret tap sequence on step 3 of the tutorial
- All handled by TriggerDetector (invisible StatefulWidget overlay, zero UI)

---

## 5. Tech Stack

| Area | Package/Tool |
|---|---|
| Framework | Flutter (Android-first) |
| Encryption | pointycastle (AES-256-CBC + PBKDF2) |
| Secure storage | flutter_secure_storage (Android) / shared_preferences (web fallback) |
| Database | sqflite / SQLCipher for notes + player stats |
| Biometrics | local_auth |
| Camera | camera (intruder selfie) |
| File picker | image_picker (photos), file_picker (audio & vault import) |
| Audio | just_audio + just_audio_web |
| Voice (v1.1) | flutter_webrtc (push-to-talk P2P audio) |
| Local networking (v1.1) | nearby_connections (WiFi/Bluetooth P2P) |
| State management | Riverpod |
| Web detection | kIsWeb from flutter/foundation.dart |
| Sharing | share_plus (vault export sharing + case file sharing) |
| Hashing | crypto (SHA-256 checksum for .mimic file integrity) |
| File paths | path_provider (Downloads directory for export) |
| Desktop SQLite (test) | sqflite_common_ffi (FFI-backed SQLite for Windows/macOS/Linux tests) |

### v1.1 New Dependencies to Add
```yaml
nearby_connections: ^4.1.0      # Local WiFi P2P
flutter_webrtc: ^0.9.47         # Push-to-talk voice
```

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
> [!IMPORTANT]
> Prioritize making an app icon that is based on our home UI to make it more creepy and interesting (e.g., incorporating elements of drifting fog, the CRT static effect, and the high-contrast crimson/voidBlack color scheme).

---

## 7. Suspicion Score & Leaderboard System

### Scoring Actions
| Action | Points |
|---|---|
| Successfully fool everyone as Mimic | +150 |
| Correctly identify the Mimic | +100 |
| Survive round innocent | +50 |
| First to correctly accuse the Mimic | +75 |
| Mimic wins in Nightmare mode | +200 |
| Special role used correctly | +50 |
| Voted out while innocent | -25 |
| Failed to vote in time | -10 |

### Rank Tiers
| Tier | Name | Score Range |
|---|---|---|
| 🩶 | Bystander | 0–499 |
| 🟢 | Suspect | 500–1,499 |
| 🔵 | Investigator | 1,500–2,999 |
| 🟣 | Phantom | 3,000–5,999 |
| 🔴 | The Original | 6,000+ |

---

## 8. Communication Rules Per Game Phase

| Phase | Mic (PTT) | Chat |
|---|---|---|
| Lobby | 🟢 Active | 🟢 Visible |
| Word Reveal | 🔴 Auto-muted | 🔴 Hidden |
| Discussion | 🟢 Active | 🟢 Visible |
| Voting | 🔴 Auto-muted | 🔴 Hidden |
| Results | 🔴 Auto-muted | 🔴 Hidden |

---

## 9. v1.1 Multiplayer Feature — Full Build Plan

### New Files — Multiplayer & Networking
| File | Purpose |
|---|---|
| `lib/game/multiplayer/nearby_service.dart` | WiFi P2P wrapper — advertise, discover, connect |
| `lib/game/multiplayer/game_sync.dart` | Game state serialization between host/guests |
| `lib/game/multiplayer/voice_service.dart` | WebRTC push-to-talk audio |
| `lib/game/multiplayer/chat_service.dart` | Text message relay during discussion phase |

### New Files — Screens
| File | Purpose |
|---|---|
| `lib/game/screens/multiplayer_menu_screen.dart` | Host vs Join choice |
| `lib/game/screens/host_lobby_screen.dart` | Room code + player list + game settings |
| `lib/game/screens/join_lobby_screen.dart` | Room code entry + waiting room |
| `lib/game/screens/tutorial_screen.dart` | Solo tutorial + hidden vault trigger on step 3 |
| `lib/game/screens/player_profile_screen.dart` | Stats, title, avatar per player |
| `lib/game/screens/case_file_screen.dart` | Post-round dramatic summary (shareable) |
| `lib/game/screens/leaderboard_screen.dart` | Local ranked leaderboard |

### New Files — Models & Services
| File | Purpose |
|---|---|
| `lib/game/models/player_profile.dart` | Profile data model + Suspicion Score logic |
| `lib/game/models/special_roles.dart` | Informant, Paranoid, Ally definitions |
| `lib/game/services/stats_service.dart` | Read/write player stats to local SQLite |
| `lib/game/services/ambience_service.dart` | Horror background audio via just_audio |

### New Files — Widgets
| File | Purpose |
|---|---|
| `lib/game/widgets/roast_card.dart` | Auto-generated post-round one-liners |
| `lib/game/widgets/push_to_talk_button.dart` | Hold-to-speak with pulsing red indicator |
| `lib/game/widgets/chat_overlay.dart` | Sliding chat panel during discussion phase |
| `lib/game/widgets/speaking_indicator.dart` | Pulsing red dot next to active speaker |

### Modified Files
| File | Change |
|---|---|
| `home_screen.dart` | Add Multiplayer, Tutorial, Leaderboard buttons |
| `mode_select_screen.dart` | Flag session as local/multiplayer, add special role toggle |
| `voting_screen.dart` | Multiplayer vote sync to host, auto-mute mic |
| `results_screen.dart` | Host broadcasts result to guests, triggers case file |
| `player_setup_screen.dart` | Avatar + profile selection per player |
| `discussion_timer_screen.dart` | Embed PTT button + chat overlay |

### Prompt Order — 20 Prompts (Gemini Flash 2.5)

**Batch A — Core Networking (4 prompts)**
1. `nearby_service.dart`
2. `game_sync.dart`
3. `voice_service.dart`
4. `chat_service.dart`

**Batch B — Lobby & Tutorial (4 prompts)**
5. `multiplayer_menu_screen.dart`
6. `host_lobby_screen.dart`
7. `join_lobby_screen.dart`
8. `tutorial_screen.dart`

**Batch C — Profiles, Stats & Leaderboard (4 prompts)**
9. `player_profile.dart` + `special_roles.dart`
10. `stats_service.dart`
11. `player_profile_screen.dart`
12. `leaderboard_screen.dart`

**Batch D — Engagement Features (4 prompts)**
13. `case_file_screen.dart`
14. `roast_card.dart` + `ambience_service.dart`
15. `push_to_talk_button.dart` + `chat_overlay.dart` + `speaking_indicator.dart`
16. `discussion_timer_screen.dart` updated

**Batch E — Modified Screens (4 prompts)**
17. `home_screen.dart` updated
18. `player_setup_screen.dart` updated
19. `voting_screen.dart` + `results_screen.dart` updated
20. `mode_select_screen.dart` updated

---

## 10. Implementation Roadmap Status

### Phase 0 — Foundation ✅
- Flutter project created
- /lib/game and /lib/vault folder structure set up
- app_theme.dart, horror_theme.dart, horror_animations.dart created
- VaultCrypto class built

### Phase 1 — Game ✅ COMPLETE
- ✅ home_screen.dart
- ✅ mode_select_screen.dart — Classic, Nightmare, Survival
- ✅ pack_select_screen.dart
- ✅ player_setup_screen.dart
- ✅ game_state.dart — Riverpod state manager
- ✅ word_reveal_screen.dart — full horror reveal flow
- ✅ voting_screen.dart — dark cards, TriggerDetector (2→0→2)
- ✅ results_screen.dart — 3-phase sequencer, confetti, TriggerDetector (score 3x)

### Phase 2 — Vault ✅ COMPLETE
- ✅ vault_crypto.dart, pin_screen.dart, vault_home_screen.dart
- ✅ photo_vault, notes, audio_vault, document_vault screens + services
- ✅ recovery_phrase.dart + bip39_wordlist.dart
- ✅ recovery_phrase_screen.dart, enter_recovery_screen.dart, reset_pin_screen.dart
- ✅ vault_exporter.dart, vault_importer.dart
- ✅ export_vault_screen.dart, import_vault_screen.dart

### Web compatibility layer ✅ COMPLETE
- ✅ platform_service.dart, kIsWeb guards, shared_preferences fallback

### Phase 3 — Polish & Safety ✅ COMPLETE
- ✅ panic_mode.dart, auto_lock.dart, breakin_log.dart
- ✅ VaultColors, VaultScaffold, PressableCard, AnimatedFAB, PinDotIndicator
- ✅ All 7 vault screens migrated to new scaffold pattern
- ✅ Zero analyzer warnings

### Phase 4 — Testing ✅ COMPLETE
- ✅ vault_crypto_test.dart, security_test.dart, vault_screens_test.dart
- ✅ game_screens_test.dart, disguise_test.dart
- ✅ recovery_phrase_screen_test.dart, enter_recovery_screen_test.dart
- ✅ vault_export_import_test.dart — 6/6 tests passing
- ✅ manual_testing_checklist.md

### Phase 5 — v1.1 Multiplayer + Engagement 🔄 IN PLANNING
- ⬜ Batch A: nearby_service, game_sync, voice_service, chat_service
- ⬜ Batch B: multiplayer_menu, host_lobby, join_lobby, tutorial_screen
- ⬜ Batch C: player_profile, special_roles, stats_service, leaderboard_screen
- ⬜ Batch D: case_file, roast_card, ambience_service, PTT + chat widgets
- ⬜ Batch E: updated home, setup, voting, results, mode_select screens

### Phase 6 — Pre-launch Prep ⬜ NOT STARTED
- Release build config (signing keystore, key.properties)
- R8/ProGuard obfuscation
- App icon & splash screen final assets
- Play Store listing (description, screenshots, content rating)
- Privacy policy (required by Google Play)
- Version & build number (pubspec.yaml production values)

### Phase 7 — Launch ⬜ NOT STARTED

---

## 11. Post-Launch Roadmap

| Version | Key features |
|---|---|
| v1.1 | Multiplayer (local WiFi), voice/chat, player profiles, leaderboard, engagement features, tutorial mode ← **IN PROGRESS** |
| v1.2 | Password manager, document/PDF vault, time-lock mode, break-in gallery |
| v2.0 | Online multiplayer, online leaderboard, secret browser, encrypted cloud backup (opt-in), custom word packs |
| v3.0 | Freemium model, multiple vault profiles, private contacts/chat logs, skin marketplace |

---

## 12. Kilocode Usage Guide (legacy — kept for reference)

> Note: Current workflow uses Gemini Flash 2.5 for all code writing. Kilocode guide kept in case of editor switch.

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

### End every Kilocode prompt with
```
Write the full complete file as a single Dart code block.
Label it: // [full file path]
Do NOT use PowerShell, terminal commands, or Add-Content.
100% complete — no partial code.
```

---

## 13. Running the App

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

---

## 14. Current Rating

**99 / 100**

| Category | Notes |
|---|---|
| Concept | 98/100 — game-as-disguise concept is highly original; the premium horror theme adds actual flavor and matches the deduction nature. |
| Security architecture | Strong — local-only, AES-256, secure in-memory decryption, TriggerDetector callback sequence tap overlays, encrypted .mimic export with SHA-256 integrity checks. |
| Disguise quality | Outstanding — complete playable horror game layer with diverse packs, modes, and dynamic animations. |
| Cross-device migration | ✅ Resolved — encrypted .mimic backup export/import with BIP39 phrase-based key derivation. No cloud required. |
| Missing point (1) | Final production hardening (Phases 6–7: app store prep, signing, obfuscation, launch). v1.1 multiplayer will push to 100/100 on completion. |

---

## 15. Open Questions & Pending Tasks

### ✅ Completed — Web Compatibility
### ✅ Completed — Phase 4 Testing & PIN Recovery
### ✅ Completed — Cross-device Migration (Vault Export/Import)

### 🔄 In Progress — v1.1 Multiplayer + Engagement Features
20-prompt build plan ready. Batches A–E defined. Awaiting build start.

### ⬜ Pending — Phase 6 Pre-launch Prep
Play Store listing, signing config, obfuscation, privacy policy. Starts after v1.1 completion.

---

## 16. Insights & Lessons Learned

- **The game-as-disguise is the app's biggest differentiator.** Most vault apps use a fake calculator. A real playable game means the cover story is airtight even when friends use it.
- **No backend is a feature, not a limitation.** Local-only storage is more private than any cloud vault app. Market it that way.
- **Kilocode defaults to PowerShell on Windows** when creating files unless explicitly told not to. The no-terminal instruction must be in every single prompt, not just the context.
- **One prompt at a time is non-negotiable.** Stacking prompts causes bugs that are hard to trace. Confirm each screen works before moving to the next.
- **The VaultCrypto class must be tested in isolation** before building anything that depends on it. Silent encryption bugs are the worst kind.
- **Decrypted data must never touch disk.** Photos, audio, and videos must be decrypted to memory only. If Kilocode writes to a temp file, correct it immediately.
- **The vault discovery moment matters.** The first time a user triggers the secret pattern should feel like finding a secret passage — the glitch animation into the clean white PIN screen is not optional polish, it's part of the experience.
- **The 14-week timeline is realistic but Phase 4 (testing) must not be shortened.** A privacy app that leaks data is worse than no app at all.
- **One cohesive visual design language binds the features.** Swapping Nunito for Creepster/Inter and establishing core dark colors binds the social deduction mechanics to a unified premium experience.
- **Form states in scrollable views require static containment.** When building screens with many validation textfields (e.g. 12 recovery phrase inputs), standard `ListView` widgets will drop widget states for off-screen fields during scroll events. Use `SingleChildScrollView` + `Column` to keep all controllers alive.
- **Binary file formats need strict validation.** The `.mimic` export format uses a magic header, version byte, and SHA-256 checksum before the JSON payload. This prevents accidental import of wrong files and catches corruption. Always validate before deserializing.
- **file_picker v11+ removed `FilePicker.platform`.** Use static methods like `FilePicker.pickFiles()` directly.
- **sqflite tests need sqflite_common_ffi, not method channel mocks.** Use `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` for real FFI-backed SQLite on desktop.
- **`getExternalStorageDirectory()` throws on non-Android.** Always wrap in try-catch — falls through to `getApplicationDocumentsDirectory()` as a safe fallback.
- **Multiplayer disguise value is underrated.** A vault app with working local voice chat between players looks nothing like a vault app. The technical complexity is exactly what makes the cover story believable.
- **Tutorial mode is the best solo disguise.** "Just showing someone how to play" is a perfect natural cover for opening the app alone without triggering suspicion.

---

## 17. How to Update This Document

This is a **living continuity document**. At the start of any new Claude session, paste this entire file to restore full context.

### Step 1 — Paste this into a new Claude session
```
Here is my Mimic project continuity document: [paste full file]
```

### Step 2 — Claude will ask about your progress
Claude will ask what was completed, what changed, and what new issues came up since the last update.

### Step 3 — Paste your progress update
Describe what phases or features were completed, which AI tools were used, any new files added, any bugs encountered, and any decisions made.

### Step 4 — Claude updates the document
Claude will update all relevant sections and deliver the updated file for download.

---

> 🎭 Built with Flutter. Designed for privacy. Disguised as fun.
> Current status: Phases 1–4 complete · BIP39 PIN Recovery integrated · Vault Export/Import complete · Web compatibility active · v1.1 Multiplayer + Engagement in planning · Rating 99/100
