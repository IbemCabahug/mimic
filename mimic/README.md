# 🎭 Mimic

A real party game. A secret vault. One app.

Mimic is a social deduction party game where players find the impostor among them — and a fully encrypted personal vault hidden behind it. Nobody suspects a game.

---

## Table of Contents
1. [Concept](#concept)
2. [How the Game Works](#how-the-game-works)
3. [The Secret Vault](#the-secret-vault)
4. [Secret Unlock Triggers](#secret-unlock-triggers)
5. [Features](#features)
6. [Tech Stack](#tech-stack)
7. [Design Direction](#design-direction)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Post-Launch Roadmap](#post-launch-roadmap)
10. [Security Notes](#security-notes)

---

## Concept
Mimic has two completely separate layers:

| Layer | What it is |
| :--- | :--- |
| **The Game** | A genuine, playable social deduction party game — find the Mimic among your friends |
| **The Vault** | An AES-256 encrypted personal safe for photos, videos, notes, audio, and documents |

The name works on both levels: the game mechanic (finding the mimic/impostor) and the app's core ability (mimicking an innocent game app).

---

## How the Game Works
* **Players join a room** — 2–8 players on one device or via a room code. One player is secretly assigned as "the Mimic."
* **A word is given** — everyone gets the same word except the Mimic, who gets a fake. Players describe their word without saying it.
* **Vote & reveal** — players vote on who they think the Mimic is. Points are awarded, rounds repeat.

The game is fully functional and genuinely fun. That's the whole point — it's a convincing cover.

---

## The Secret Vault
Once unlocked, the vault gives you access to:
* 📷 **Photo & Video vault** — import from gallery, originals auto-deleted, encrypted grid view with album support
* 📝 **Encrypted notes** — rich text, pin favourites, search, auto-lock on exit
* 🎵 **Audio locker** — import audio/music, built-in encrypted player, playlist support
* 📄 **Document vault** — store PDFs, IDs, certificates, and sensitive files

---

## Secret Unlock Triggers
The vault is never accessible from an obvious button. It can only be opened through hidden triggers built into the game:

| Trigger | How it works |
| :--- | :--- |
| **Voting pattern** | On the voting screen, tap players in a specific secret order — vault opens |
| **Logo long-press** | Long-press the Mimic logo on the main menu for 3 seconds, then swipe up |
| **Score screen code** | After a game ends, tap the score numbers in a secret sequence (Konami-style) |
| **Solo practice mode** | Enter a specific fake "player name" in the solo mode to reveal the PIN prompt |

After a trigger is detected, a brief glitch animation plays → fade to the PIN entry screen.

---

## Features

* **Disguised Game Shell**: Looks, acts, and plays like a genuine horror party game.
* **PIN-Protected Encrypted Vault**: Hidden behind secret in-game tap gestures.
* **Vault Sections**: Separate encrypted databases/directories for Photos, Videos, Notes, Audio, and Documents.
* **Move-to-Vault & Restore-to-Gallery**: Imports media into the vault (originals deleted from gallery after system consent) and allows restoring them back (moving back to gallery).
* **Dual Biometric Unlock**: Fingerprint/face unlock with shake-routing for either admin panel access or the secret vault.
* **Duress / Decoy PIN**: Inputting a duress PIN redirects to a mock Admin Panel; decoy PIN opens an empty fake vault.
* **Shake-to-Hide**: A non-destructive shake gesture immediately clears the in-memory keys, returns to the game disguise, and displays a temporary blood-splatter overlay (no data deleted, no wiped/recovery UI shown).
* **12-Word BIP39 Recovery & Encrypted Backup**: Recover access with a 12-word phrase or export/import encrypted `.mimic` backups.
* **Panic / PIN Wipe**: Self-destruct PIN wipe after consecutive failed entries and instant panic locking.

---

## Tech Stack

| Area | Choice | Reason |
| :--- | :--- | :--- |
| **Framework** | Flutter | Single codebase for Android + iOS, great for game-style UI and animations |
| **Encryption** | AES-256 + PBKDF2 | Industry standard; `pointycastle` package |
| **Secure storage** | `flutter_secure_storage` | PIN and key storage |
| **Database** | SQLCipher | Encrypted SQLite for notes |
| **Local files** | Encrypted binary blobs | All media stored encrypted on device |
| **Biometrics** | `local_auth` package | Fingerprint + Face ID |

---

## Design Direction

### Two personalities, one app
The game layer and vault layer have completely different visual identities — intentionally.

#### Game layer (the disguise)
* **Background**: `#0F0F14` — deep dark
* **Primary accent**: `#7F77DD` — mimic purple
* **Secondary**: `#1D9E75` — safe teal
* **Alert**: `#D85A30` — coral
* **Font**: Space Grotesk or Nunito — bold, playful, game-like
* Subtle particle animation on the home screen background

#### Vault layer (the real app)
* **Background**: `#FFFFFF` — clean white
* **Surface**: `#F1EFE8` — warm off-white
* **Accent**: `#534AB7` — deep purple
* **Muted text**: `#888780`
* **Font**: Inter or DM Sans — clean, minimal, trustworthy

The visual shift from dark game → light vault signals "you're in the secret area now" without any words.

#### App icon
A stylized face split diagonally — one half normal, one half glitchy/distorted. Dark background with a subtle purple glow. Looks like a game icon at a glance. Tells no story about a vault. Must read clearly at 60×60px.

#### Transition animation
When the secret trigger fires → brief glitch/static effect (0.3s) → fade to clean white PIN screen. The "breaking through" effect sells the feeling of crossing into a hidden layer.

#### Vault discovery moment
When a user first discovers and triggers the unlock for the very first time, a special "Welcome to the vault" animation plays. Make it feel like finding a secret passage — rewarding and memorable.

---

## Implementation Roadmap

### Phase 0 — Foundation (Week 1–2)
- [x] Set up Flutter project with `/game` and `/vault` module folders (kept separate — vault is never imported by game code)
- [x] Install and test encryption library (`pointycastle`, `flutter_secure_storage`)
- [ ] Write `VaultCrypto` class — all encryption/decryption goes through here
- [ ] Define design tokens (colors, fonts, spacing) for both game and vault themes

### Phase 1 — Build the game (Week 3–5)
- [ ] Home screen — Mimic logo, Play button, Settings
- [ ] Player setup screen — enter 2–8 player names, assign avatars/colors
- [ ] Word assignment screen — private reveal per player, pass-and-play
- [ ] Discussion timer screen — countdown with animated timer bar
- [ ] Voting screen — tap to vote; secret trigger listener runs silently here
- [ ] Results & scoreboard screen — reveal the Mimic, show points, play again

### Phase 2 — Build the vault (Week 6–8)
- [ ] `TriggerDetector` class — listens for secret tap pattern, fires on match
- [ ] PIN entry screen — minimal design, wrong PIN silent fail, intruder selfie on 3 fails
- [ ] Vault home screen — grid of 4 sections (Photos/Videos, Notes, Audio, Documents)
- [ ] Photo & video vault — import, encrypt, auto-delete originals, album view
- [ ] Notes vault — create/edit encrypted notes, pin, search, auto-lock
- [ ] Audio vault — import, encrypted player, playlist support

### Phase 3 — Polish & safety (Week 9–10)
- [ ] Panic mode — triple-press power → instant lock + clear recent apps thumbnail
- [ ] Decoy PIN — second PIN that opens a convincing empty vault
- [ ] Intruder selfie system — silent front camera on failed unlock attempts
- [ ] Break-in log — encrypted timestamp log of all attempts
- [ ] Auto-lock rules — background, notification, screen-off, inactivity timeout (configurable)
- [ ] Recent apps disguise — screenshot game home screen when vault is backgrounded

### Phase 4 — Testing (Week 11–12)
- [ ] Security audit — extract app storage folder, confirm files unreadable without PIN
- [ ] Verify recent apps switcher never shows vault contents
- [ ] Disguise stress test — hand phone to someone unfamiliar, watch for suspicion
- [ ] Game playability test — 5–10 full rounds with real people
- [ ] Edge case vault testing — low storage, corrupt import, mid-import kill, PIN change
- [ ] Performance test — 50-photo batch encrypt/decrypt, 500MB video, vault opens in <2s

### Phase 5 — Pre-launch prep (Week 13)
- [ ] App store listing — game-only description, 5–6 game-only screenshots, no vault mention
- [ ] Privacy policy — all data local, no cloud, no analytics
- [ ] Onboarding flow — 3-step game tutorial on first launch; vault onboarding triggered on first discovery
- [ ] Vault discovery animation — glitch reveal on first-ever unlock
- [ ] App icon finalised — split-face design, tested at 60×60px

### Phase 6 — Launch (Week 14)
- [ ] Install on personal device — use as real vault for 1–2 weeks before sharing
- [ ] Beta — share with 5–10 trusted people, collect bugs and feedback
- [ ] Submit to Google Play (review ~3 days)
- [ ] Submit to Apple App Store (review ~7 days)

---

## Post-Launch Roadmap

### v1.1 — Quick wins
* More disguise skin themes
* Expanded word packs for the game
* Encrypted backup to local/external storage
* Fake home screen widget (looks like a utility widget)

### v1.2 — Core expansion
* Password manager section inside vault
* Document & PDF vault with folder organisation
* Time-lock mode
* Break-in gallery (view intruder selfies)

### v2.0 — Big features
* Online multiplayer for the game
* Secret built-in browser (history and bookmarks stored in vault)
* Encrypted cloud backup (opt-in, end-to-end)
* Custom word packs (user-created)

### v3.0 — Vision
* Freemium model (free tier: 1 skin, 500MB vault; Pro: unlimited)
* Multiple vault profiles
* Private contacts and chat log storage
* Disguise skin marketplace

---

## Security Model

* **Encryption**: Files are individually encrypted using AES-256-CBC. SQLite databases (such as notes and video metadata) are protected via SQLCipher.
* **Key Derivation**: Master keys are derived from the user PIN using PBKDF2 with 100,000 iterations.
* **Key Storage**: Derived keys and hashes are stored in local platform secure storage using `flutter_secure_storage` with Android's `encryptedSharedPreferences: true` enabled. Note that switching or updating the secure storage configuration requires a clean app reinstall.
* **Encrypted Files**: All encrypted media and database assets are saved inside the application's persistent documents directory.
* **Key Lifecycle**: Cryptographic keys reside only in ephemeral memory when the vault is unlocked. Action triggers like Auto-Lock or Shake-to-Hide instantly clear this memory key (`VaultCrypto.clearKey()`).
* **Recovery**: PIN recovery is possible only through the 12-word BIP39 phrase. Losing both the PIN and the recovery phrase means permanent loss of access.
* **Decoy / Duress Routing**: Entering a decoy PIN opens an empty vault. Entering a duress PIN routes the app to a mock `AdminPanelScreen` instead of the vault.
* **Shake-to-Hide (Non-Destructive)**: Shaking the device locks the vault silently by clearing the in-memory key, routing back to the game, and showing an animated blood-splatter. No database entries, files, PIN hashes, or biometric secrets are modified or deleted.
* **Commit History Reference**: The recovery phrase and backup/migration features were introduced in commit `a233255`.
* **Isolation**: The game layer and vault layer are completely isolated — no shared imports or state.
* **Network Privacy**: The app never requests network permissions for vault functionality — all encryption is local.

---
*Built with Flutter. Designed for privacy. Disguised as fun.*
