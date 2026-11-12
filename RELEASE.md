# Mimic — Android Release

> A free word-guessing party game. Play on one phone or over local Wi-Fi.

Mimic is free to download and play. The app and its Android releases belong in
the main Mimic repository. No activation code is needed to get started.

## Download

Open [Releases](https://github.com/IbemCabahug/mimic/releases) in the
[main repository](https://github.com/IbemCabahug/mimic), choose a published release,
and download the attached `app-release.apk`.

Requires Android 7.0 or newer. A universal APK includes multiple Android CPU
architectures; check the release requirements for compatibility.

## Installing and Updating

1. Download `app-release.apk` from the main repository's Releases page.
2. Open it on your Android phone.
3. If prompted, allow your browser or file manager to install from this source.
4. Tap **Install**. You can turn that permission off again afterward.

For an update, install **over your existing copy**. Updates require the same app
identity and signing key. Do not uninstall or clear app data first.

### If an Update Fails

**Do not uninstall Mimic to fix an installation error.** Uninstalling or clearing
app data can permanently remove locally stored data and encryption keys.

If Android reports a downgrade or signature mismatch, stop and report your phone
model, Android version, and the exact error text. Do not include private content.

## Playing Together

- Pass one phone around for local play.
- For separate phones, connect everyone to the same Wi-Fi network or a player's
  hotspot, then create or join a room.
- Internet access is not needed for local multiplayer.

## Open Your First Vault

Mimic also includes a private vault. For first-time setup, use **local play on one
phone**, not a multiplayer room:

1. Tap **PLAY → CLASSIC**, select a word pack, and add exactly three players in
   this order: **A, B, C**. Start the game.
2. Complete the word reveals and continue through discussion to **VOTING**.
3. Select **A** for voter A and tap **SUBMIT VOTE**; select **C** for voter B and
   submit; select **B** for voter C and submit. This is **first → third → second**
   player. Keep less than **three seconds between vote submissions**. Selecting
   cards without submitting does not count.
4. After the brief flash, create a private **4–8 digit PIN** and confirm it.
5. Choose your own **three-tap unlock sequence** and repeat it to confirm. The
   three taps cannot all be identical. Remember the player positions you chose.
6. Write down the **12 recovery words in order**, store them safely outside the
   app, and complete the on-screen confirmation. Never share your PIN or words.

To return later, use a local game's voting screen and submit votes for your saved
player-position sequence, keeping less than three seconds between submissions,
then enter your PIN. Use enough players for the positions in your sequence.
After setup, use your personal sequence—not the first-time setup order.

The vault's **? → Field Manual** provides more help. If first-time entry fails,
retry in a new three-player local game, checking the vote order and timing. If a
vault already exists, use its saved sequence. **Never uninstall or clear app data
to restart setup**; doing so can permanently remove your local data and keys.

## v1.4.4 — Build 3013

This Android build is **1.4.4 (3013)**. It focuses on a simpler interface and
preserves existing user data when installed as a correctly signed update.

Release tag: **v1.4.4-build.3013**. This distinguishes the build from older releases
with the same display version without replacing existing tags.

- APK size: **98,995,241 bytes**
- Package: `com.ibem.mimic`
- SHA-256: `bf5b7f7b1a0bdd467063cb235bfd7db0f695dcc4c32eb236448e44c34283358d`
- Signing certificate SHA-256: `8e8ffd75133a303fc3bf4edcb3707922dbf34b71d58798fcd24a6ef2d02a579c`

Package/version, APK signature and Android alignment checks passed. On-device
installation/gameplay testing has not been performed for this build, and full
static analysis has not completed. No analyzer pass is claimed. Do not install
over a higher version code or uninstall to bypass an update rejection.

## Earlier Changes

- **v1.4.3** — faster first playback for newly imported videos.
- **v1.4.2** — improved return navigation and local-data stability.

## Reporting Issues

Message the maintainer with your app version, phone model, Android version, and
steps to reproduce the problem. For installation failures, include the exact
error text. Never attach private app content or sensitive screenshots.
