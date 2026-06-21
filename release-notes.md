## 1.3.0

### 🎬 Video vault — streaming playback
- Encrypted videos now stream directly to the player instead of being fully decrypted to disk first: faster start, smoother seeking, and far less temporary storage used.
- Media is served over a loopback-only local connection secured with a per-session token that is torn down when the vault locks.

### 🔐 Security & auto-lock
- The vault now locks automatically when you leave the app (switch apps / go to home) and locks instantly on return once the idle timeout has passed.
- Auto-lock no longer interrupts you while a large video is loading or playing.
- Media encryption migrated to a streaming-friendly mode (CTR) to support range requests.

### 💾 Backup & restore
- New .mimic backup format (v2) for streaming backup and restore, with v1 backward compatibility.
- Free-space checks before export and import to avoid failures partway through.
- Fixed a crash when exporting large vaults.
- Lifted export size cap to support large vaults.

### 🛠 Fixes & polish
- Fixed an audio playback race condition.
- Reverted app icon back to the original Mimic icon.
