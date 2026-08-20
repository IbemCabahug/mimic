Updates to track:
Build status becomes:

✅ Phase 1 (game — all screens) — COMPLETE
✅ Phase 2 (vault) — COMPLETE
✅ Phase 3 (polish & safety) — COMPLETE
✅ Phase 4 (testing) — COMPLETE
⬜ Phase 5 (pre-launch prep) — not started
⬜ Phase 6 (launch) — not started

New stages to add to chronological overview:
Stage 14 — Phase 3 completed (polish & safety)
Phase 3 was built using Anthropic Opus and Gemini 3.5 Flash (High) instead of Kilocode. Security core (glitch transition, panic mode, auto-lock, break-in log) was built in one batch. Polish was applied in a second batch. Completed work included: unified vaultTheme design tokens (VaultColors helper class, full component-level styling), VaultScaffold wrapper with AutoLockWrapper integration, three micro-animation widgets (PressableCard, AnimatedFAB, PinDotIndicator), and migration of all 7 vault screens to the new scaffold pattern (vault_home, photo_vault, notes, audio_vault, document_vault, vault_settings, breakin_log). Router-level wrappers cleaned up in game.dart. All tests passed, zero analyzer warnings.

Stage 15 — Phase 4 completed (testing)
Completed comprehensive testing coverage for the game and vault layers:
1. **Crypto Verification**: Wrote unit tests in `test/vault/crypto/vault_crypto_test.dart` checking PBKDF2 key derivation, random IV encryption round-trips, salt storage, and tamper-resistance.
2. **Security & Core Logics**: Wrote widget and unit tests in `test/vault/security/security_test.dart` covering TriggerDetector callbacks, PinScreen security mock-ups, AutoLock timer resets, and break-in log selfie encryptions.
3. **Vault Screens**: Wrote widget tests in `test/vault/screens/vault_screens_test.dart` for all 7 vault screens (including the newly added document vault and settings screens) verifying VaultScaffold, AutoLockWrapper, vaultTheme adherence, and zero plaintext file leaks.
4. **Game Screens & State**: Wrote widget and unit tests in `test/game/screens/game_screens_test.dart` covering the home screen, setup screen, reveals, voting, results, and GameStateNotifier unit tests.
5. **Stealth Integration**: Wrote integration tests in `test/integration/disguise_test.dart` simulating OS-level features (recents thumbnail protection, FLAG_SECURE method channels, hardware volume key panic triggers, back-stack purging, and manifest label checks).
6. **Device Checklist**: Generated `manual_testing_checklist.md` in the artifacts folder detailing hardware-level verification checks (Digital Wellbeing masking, gallery containment, adb logcat checks, clipboard scrubs, keyboard auto-fill Blocks, split-screen restrictions, and screen pinning blocks).
7. **Security Findings**: Highlighted architectural gaps (lack of native lifecycle observers for active/inactive states, and missing volume key/FLAG_SECURE native integrations) to guide subsequent development phases.

Stage 16 — Phase 2 Security Hardening & Background Crypto Isolates (v1.4.1+)
Completed deep security hardening, media streaming, and isolate architecture across the vault subsystem (total test suite reached 319 passing tests):
1. **Versioned KDF Parameters (Phase 2A)**: Implemented `v3:` verifier records with explicit iteration counts while freezing legacy `v2:` compatibility at 100,000 iterations; unified recovery phrase and duress PIN KDF handling.
2. **Native PBKDF2 Offloading (Phase 2B)**: Offloaded key derivation to native Android Kotlin `SecretKeyFactory` over `KeystoreChannel` with verified Dart fallback, eliminating main-thread unlock freezes and ANRs on mobile hardware.
3. **Android Keystore Hardware Key-Wrapping (Phase 2C)**: Master Key KEK/DEK architecture backed by Android Keystore, with atomic 3-stage key swaps (`_tmpSalt`, `_tmpPinHash`, `_tmpMasterWrapped`) and self-healing recovery.
4. **SQLite Concurrency & Recovery (Phase 2D / 2G-1)**: Single-flight `_ensureDb()` deduplication across photo, video, and note services to eliminate double-open races, plus automatic handle reopening on closed SQLite connections.
5. **Media Streaming & Seeking (Phase 2E / 2F)**: In-memory tokenized `MediaStreamServer` and AES-CTR streaming range requests (`MVKEYc1\0`) for fast video seeking, with non-destructive lazy migration of legacy CBC blobs.
6. **AutoLock Lifecycle & Error Sanitization (Phase 2G-2..4)**: Implemented import suspension in `AutoLock` with a 5-minute background ceiling, and sanitized user-facing import error messages.
7. **Background Crypto Worker Isolates (Phase 2H)**: Created `crypto_isolate.dart` for streaming CBC encryption and decryption on dedicated background isolates with format compatibility, caller/worker key zeroing, typed wire error handling, and dead-isolate detection. Total test suite: 319 passed tests.