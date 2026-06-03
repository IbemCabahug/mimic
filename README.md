[README.md](https://github.com/user-attachments/files/28542485/README.md)
# 🎭 Mimic

> A real party game. A secret vault. One app.

Mimic is a social deduction party game where players find the impostor among them — and a fully encrypted personal vault hidden behind it. Nobody suspects a game.

---

## Table of Contents

- [Concept](#concept)
- [How the Game Works](#how-the-game-works)
- [The Secret Vault](#the-secret-vault)
- [Secret Unlock Triggers](#secret-unlock-triggers)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Design Direction](#design-direction)
- [Implementation Roadmap](#implementation-roadmap)
- [Post-Launch Roadmap](#post-launch-roadmap)
- [Security Notes](#security-notes)

---

## Concept

Mimic has two completely separate layers:

| Layer | What it is |
|---|---|
| **The Game** | A genuine, playable social deduction party game — find the Mimic among your friends |
| **The Vault** | An AES-256 encrypted personal safe for photos, videos, notes, audio, and documents |

The name works on both levels: the game mechanic (finding the mimic/impostor) and the app's core ability (mimicking an innocent game app).

---

## How the Game Works

1. **Players join a room** — 2–8 players on one device or via a room code. One player is secretly assigned as "the Mimic."
2. **A word is given** — everyone gets the same word except the Mimic, who gets a fake. Players describe their word without saying it.
3. **Vote & reveal** — players vote on who they think the Mimic is. Points are awarded, rounds repeat.

The game is fully functional and genuinely fun. That's the whole point — it's a convincing cover.

---

## The Secret Vault

Once unlocked, the vault gives you access to:

- 📷 **Photo & Video vault** — import from gallery, originals auto-deleted, encrypted grid view with album support
- 📝 **Encrypted notes** — rich text, pin favourites, search, auto-lock on exit
- 🎵 **Audio locker** — import audio/music, built-in encrypted player, playlist support
- 📄 **Document vault** — store PDFs, IDs, certificates, and sensitive files

---

## Secret Unlock Triggers

The vault is never accessible from an obvious button. It can only be opened through hidden triggers built into the game:

| Trigger | How it works |
|---|---|
| **Voting pattern** | On the voting screen, tap players in a specific secret order — vault opens |
| **Logo long-press** | Long-press the Mimic logo on the main menu for 3 seconds, then swipe up |
| **Score screen code** | After a game ends, tap the score numbers in a secret sequence (Konami-style) |
| **Solo practice mode** | Enter a specific fake "player name" in the solo mode to reveal the PIN prompt |

After a trigger is detected, a brief glitch animation plays → fade to the PIN entry screen.

---

## Features

### Security
- AES-256 file encryption, SQLCipher for the notes database
- Keys derived from PIN via PBKDF2 — never stored in plain text
- Biometric unlock (fingerprint / Face ID) support
- Decoy PIN — opens a convincing empty vault under pressure
- Intruder selfie — silent front camera photo after 3 failed PIN attempts
- Self-destruct mode — wipe vault after N wrong attempts (configurable)
- Time-lock mode — lock vault for a set period
- Break-in log — timestamps of every failed unlock attempt, stored encrypted

### Disguise
- App icon and name look like a normal party game
- Recent apps switcher shows the game screen — never the vault
- Auto-lock on: app backgrounded, notification received, screen off, inactivity timeout
- Panic mode — triple-press power button to instantly lock and return to game screen
- Transformable disguise skins (future: calculator, weather, utility, wallpaper browser)

### Vault
- Import photos/videos from gallery with optional auto-delete of originals
- Full-screen viewer with swipe navigation
- Encrypted note editor with search and pin support
- Built-in audio player for locked music/audio files
- All data stored locally — no cloud by default

---

## Tech Stack

| Area | Choice | Reason |
|---|---|---|
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
- **Background:** `#0F0F14` — deep dark
- **Primary accent:** `#7F77DD` — mimic purple
- **Secondary:** `#1D9E75` — safe teal
- **Alert:** `#D85A30` — coral
- **Font:** Space Grotesk or Nunito — bold, playful, game-like
- Subtle particle animation on the home screen background

#### Vault layer (the real app)
- **Background:** `#FFFFFF` — clean white
- **Surface:** `#F1EFE8` — warm off-white
- **Accent:** `#534AB7` — deep purple
- **Muted text:** `#888780`
- **Font:** Inter or DM Sans — clean, minimal, trustworthy

> The visual shift from dark game → light vault signals "you're in the secret area now" without any words.

### App icon
A stylized face split diagonally — one half normal, one half glitchy/distorted. Dark background with a subtle purple glow. Looks like a game icon at a glance. Tells no story about a vault. Must read clearly at 60×60px.

### Transition animation
When the secret trigger fires → brief glitch/static effect (0.3s) → fade to clean white PIN screen. The "breaking through" effect sells the feeling of crossing into a hidden layer.

### Vault discovery moment
When a user first discovers and triggers the unlock for the very first time, a special "Welcome to the vault" animation plays. Make it feel like finding a secret passage — rewarding and memorable.

---

## Implementation Roadmap

### Phase 0 — Foundation `Week 1–2`
- [ ] Set up Flutter project with `/game` and `/vault` module folders (kept separate — vault is never imported by game code)
- [ ] Install and test encryption library (`pointycastle`, `flutter_secure_storage`)
- [ ] Write `VaultCrypto` class — all encryption/decryption goes through here
- [ ] Define design tokens (colors, fonts, spacing) for both game and vault themes

### Phase 1 — Build the game `Week 3–5`
- [ ] Home screen — Mimic logo, Play button, Settings
- [ ] Player setup screen — enter 2–8 player names, assign avatars/colors
- [ ] Word assignment screen — private reveal per player, pass-and-play
- [ ] Discussion timer screen — countdown with animated timer bar
- [ ] Voting screen — tap to vote; **secret trigger listener runs silently here**
- [ ] Results & scoreboard screen — reveal the Mimic, show points, play again

### Phase 2 — Build the vault `Week 6–8`
- [ ] `TriggerDetector` class — listens for secret tap pattern, fires on match
- [ ] PIN entry screen — minimal design, wrong PIN silent fail, intruder selfie on 3 fails
- [ ] Vault home screen — grid of 4 sections (Photos/Videos, Notes, Audio, Documents)
- [ ] Photo & video vault — import, encrypt, auto-delete originals, album view
- [ ] Notes vault — create/edit encrypted notes, pin, search, auto-lock
- [ ] Audio vault — import, encrypted player, playlist support

### Phase 3 — Polish & safety `Week 9–10`
- [ ] Panic mode — triple-press power → instant lock + clear recent apps thumbnail
- [ ] Decoy PIN — second PIN that opens a convincing empty vault
- [ ] Intruder selfie system — silent front camera on failed unlock attempts
- [ ] Break-in log — encrypted timestamp log of all attempts
- [ ] Auto-lock rules — background, notification, screen-off, inactivity timeout (configurable)
- [ ] Recent apps disguise — screenshot game home screen when vault is backgrounded

### Phase 4 — Testing `Week 11–12`
- [ ] Security audit — extract app storage folder, confirm files unreadable without PIN
- [ ] Verify recent apps switcher never shows vault contents
- [ ] Disguise stress test — hand phone to someone unfamiliar, watch for suspicion
- [ ] Game playability test — 5–10 full rounds with real people
- [ ] Edge case vault testing — low storage, corrupt import, mid-import kill, PIN change
- [ ] Performance test — 50-photo batch encrypt/decrypt, 500MB video, vault opens in <2s

### Phase 5 — Pre-launch prep `Week 13`
- [ ] App store listing — game-only description, 5–6 game-only screenshots, no vault mention
- [ ] Privacy policy — all data local, no cloud, no analytics
- [ ] Onboarding flow — 3-step game tutorial on first launch; vault onboarding triggered on first discovery
- [ ] Vault discovery animation — glitch reveal on first-ever unlock
- [ ] App icon finalised — split-face design, tested at 60×60px

### Phase 6 — Launch `Week 14`
- [ ] Install on personal device — use as real vault for 1–2 weeks before sharing
- [ ] Beta — share with 5–10 trusted people, collect bugs and feedback
- [ ] Submit to Google Play (review ~3 days)
- [ ] Submit to Apple App Store (review ~7 days)

---

## Post-Launch Roadmap

### v1.1 — Quick wins
- More disguise skin themes
- Expanded word packs for the game
- Encrypted backup to local/external storage
- Fake home screen widget (looks like a utility widget)

### v1.2 — Core expansion
- Password manager section inside vault
- Document & PDF vault with folder organisation
- Time-lock mode
- Break-in gallery (view intruder selfies)

### v2.0 — Big features
- Online multiplayer for the game
- Secret built-in browser (history and bookmarks stored in vault)
- Encrypted cloud backup (opt-in, end-to-end)
- Custom word packs (user-created)

### v3.0 — Vision
- Freemium model (free tier: 1 skin, 500MB vault; Pro: unlimited)
- Multiple vault profiles
- Private contacts and chat log storage
- Disguise skin marketplace

---

## Security Notes

- The vault key is derived from the user's PIN using PBKDF2 and is never written to disk in plain text
- All files are encrypted individually using AES-256 before being written to storage
- The game layer and vault layer are completely isolated — no shared imports or state
- There is no "forgot PIN" recovery by design — losing the PIN means losing access to vault contents
- The app never requests network permissions for vault functionality — all encryption is local

---

> Built with Flutter. Designed for privacy. Disguised as fun.
