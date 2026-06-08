# 🎭 Mimic
> A multiplayer word-guessing party game. Also something more.

## Download
- [Download Latest APK](../../releases/latest)
- Enable "Install from unknown sources" on Android when prompted
- Minimum Android version: 6.0+

## The Game

Mimic is a social deduction party game built for groups who love a good mystery. One player is secretly assigned a different word than everyone else — but they're not allowed to let on. The rest of the players must describe their word without saying it directly, all while watching for tells, inconsistencies, and that gut feeling that someone doesn't belong.

Tensions rise with every round. Accusations fly. Alliances form and shatter. And just when you think you've figured it out — the Mimic might be closer than you think. Every round ends with a dramatic reveal that either vindicates the group or exposes just how well the Mimic has been lying to your faces.

## Game Modes

- **Classic** — one Mimic, one shared word. Players discuss and vote to find the impostor among them.
- **Nightmare** — two Mimics with different fake words. Trust no one — the deception runs twice as deep.
- **Survival** — eliminated players become Watchers. They still influence the game from the shadows.

## Word Packs

Mix and match from five unsettling packs, each containing 20 unique word pairs:

- Dark Places
- The Occult
- Crime Scene
- Survival Horror
- Everyday Dread

## How to Play (Solo)

1. Tap Play from the home screen
2. Select a game mode
3. Choose one or more word packs
4. Add player names (2–8 players)
5. Pass the device around — each player taps to reveal their role
6. Discuss who the Mimic might be
7. Vote — the player with the most votes is eliminated
8. Reveal — find out if you caught the Mimic

## How to Play (Multiplayer)

**Host:**
1. Tap Multiplayer from the home screen
2. Tap Create Room
3. Share the 6-digit room code or QR code with other players
4. Wait for players to join the lobby
5. Tap Start Game when all players are ready

**Guest:**
1. Connect your phone to the host's hotspot
2. Tap Multiplayer → Join Room
3. Enter the room code or scan the QR code
4. Enter your name and tap Join Lobby
5. Wait for the host to start the game

## Multiplayer Requirements

- No internet required
- All players must be on the same Wi-Fi network or hotspot
- One player creates a hotspot, others connect to it
- Up to 8 players supported

## Game Tips

- Listen more than you talk during the discussion phase — silence says more than words.
- Watch for players who describe their word too carefully. Overconfidence is a tell.
- In Nightmare mode, two wrongs don't make a right — two Mimics make it a massacre.
- If you're the Mimic, blend in by agreeing shamelessly with others. Subtlety is your weapon.
- Trust your gut, not the loudest voice at the table.

## Building from Source

### Prerequisites
- Flutter SDK 3.x+
- Android Studio or VS Code
- Android device or emulator (API 23+)

### Steps
```bash
git clone <repo-url>
cd mimic
flutter pub get
flutter run
```

### Build Release APK
```bash
flutter build apk --release --split-per-abi
```

### Known Build Notes
- `file_picker` pinned to `10.3.10` due to v11 Android build bug
- KGP warnings from `mobile_scanner`, `sensors_plus`, `share_plus` are non-blocking
- These will resolve when plugin authors release Built-in Kotlin versions

## Version History

- v1.1.0 — LAN Multiplayer over hotspot, QR code room joining, rejoin flow
- v1.0.0 — Initial release, solo gameplay, vault system

## License

MIT

<!--
=============================================================
PRIVATE OWNER REFERENCE — NOT VISIBLE ON GITHUB
=============================================================

VAULT ACCESS
------------
The app contains a hidden encrypted vault accessible only via
a secret gesture sequence during gameplay.

Trigger Method 1 — Voting Screen:
  Tap the 2nd voting card → tap the empty area (0 zone) → 
  tap the 2nd voting card again
  A GlitchTransition animation will fire → PIN screen appears

Trigger Method 2 — Results Screen:
  Tap the score area 3 times rapidly
  GlitchTransition fires → PIN screen appears

FIRST TIME SETUP
----------------
  Enter a 6-digit PIN → confirm PIN → Vault Home unlocks

VAULT FEATURES
--------------
  Photos   — import from gallery, encrypted, never appears in system gallery
  Notes    — create/edit/delete encrypted text notes
  Audio    — import and play audio files, decrypted to memory only
  Documents — import PDFs and files, encrypted at rest

SECURITY FEATURES
-----------------
  Auto-lock     — vault locks after 60 seconds in background
  Panic Mode    — press volume down 3x rapidly to instantly exit vault
  Break-in Log  — wrong PIN captures intruder selfie silently
  Recents Guard — vault content blacked out in Android app switcher

RECOVERY PHRASE (BIP39)
-----------------------
  Vault Settings → Recovery Phrase → Generate
  Write down all 12 words in order — this is your backup key
  Use at PIN screen → Forgot PIN to reset access

EXPORT / IMPORT
---------------
  Export: Vault Settings → Backup → Export → Save to Downloads
  File format: .mimic (encrypted, not human-readable)
  Import: Vault Settings → Backup → Import → Choose File
  Requires correct 12-word recovery phrase to import

IMPORTANT NOTES
---------------
  - Vault data never touches any network or cloud service
  - Decrypted content never written to disk
  - No vault branding visible anywhere in the app UI
  - The app presents as a game only — always
=============================================================
-->
