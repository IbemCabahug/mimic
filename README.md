# 🎭 Mimic
> A free word-guessing party game for Android. Play on one phone or over local Wi-Fi.

## Download
- [Download Latest APK](../../releases/latest)
- Enable "Install from unknown sources" on Android when prompted
- Minimum Android version: 7.0+
- [Installation and release guide](RELEASE.md)

Mimic is free to download and play from this repository. No activation code is
needed to get started.

**Updating? Install over your existing copy. Do not uninstall or clear app data
to fix an installation error.** Report signature or downgrade errors instead.

## The Game

Mimic is a social deduction party game built for groups who love a good mystery. One player is secretly assigned a different word than everyone else — but they're not allowed to let on. The rest of the players must describe their word without saying it directly, all while watching for tells, inconsistencies, and that gut feeling that someone doesn't belong.

Tensions rise with every round. Accusations fly. Alliances form and shatter. And just when you think you've figured it out — the Mimic might be closer than you think. Every round ends with a dramatic reveal that either vindicates the group or exposes just how well the Mimic has been lying to your faces.

## Game Modes

- **Classic** — one Mimic, one shared word. Players discuss and vote to find the impostor among them.
- **Nightmare** — two Mimics with different fake words. Trust no one — the deception runs twice as deep.
- **Survival** — eliminated players become Watchers. They still influence the game from the shadows.

## Word Packs

Choose from themed word packs and mix up to three for a game:

- Dark Places
- The Occult
- Crime Scene
- Survival Horror
- Everyday Dread
- Philippine Folklore

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
- Flutter SDK with Dart 3.12 or newer, compatible with `mimic/pubspec.yaml`
- Android Studio or VS Code
- Android device or emulator (API 24+)

### Steps
```bash
git clone https://github.com/IbemCabahug/mimic.git
cd mimic/mimic
flutter pub get
flutter run
```

### Build Release APK (universal — one file, any supported phone)

From the Flutter application directory (`mimic/`), build the public Android app:

```powershell
powershell -NoProfile -File tool\build_release.ps1 -FreeTierOnly
```

No activation credentials are required. Configure release signing locally; never
commit a keystore or signing passwords. Output:
`build/app/outputs/flutter-apk/app-release.apk`. Keep generated debug symbols private.

Before distribution, verify the APK version, package (`com.ibem.mimic`), signing
certificate, and SHA-256 checksum. A source version change does not prove a new
APK was built. Updates must use the same signing key as the installed app.

> The version code comes from `pubspec.yaml` (`version: x.y.z+N`). It must only
> ever rise — a lower build number cannot install over a distributed one, and
> uninstalling Mimic or clearing app data can permanently remove local data and
> encryption keys. Do not use either as an update troubleshooting step.

### Known Build Notes
- `file_picker` pinned to `10.3.10` due to v11 Android build bug
- KGP warnings from `mobile_scanner`, `sensors_plus`, `share_plus` are non-blocking

## Version History

- v1.4.4 (build 3013) — signed Android build with a simpler interface; see Releases for the APK, checksum, and validation limitations
- v1.4.3 — faster first playback for newly imported videos
- v1.1.0 — LAN Multiplayer over hotspot, QR code room joining, rejoin flow
- v1.0.0 — Initial release, solo gameplay, vault system

## License

MIT
