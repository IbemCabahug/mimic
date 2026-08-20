// lib/vault/crypto/media_format.dart

/// AES-CBC media streaming magic header: "MVKEYv1\0" (keyed by master DEK).
const List<int> kMediaMagicV1 = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x76, 0x31, 0x00];

/// Legacy AES-CTR media streaming magic header: "MVKEYc1\0" (keyed by system key).
const List<int> kMediaMagicCtrV1 = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x63, 0x31, 0x00];

/// AES-CTR media streaming magic header: "MVKEYc2\0" (keyed by master DEK).
const List<int> kMediaMagicCtrV2 = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x63, 0x32, 0x00];

/// Returns true if [head] plausibly begins a video container we write to the vault.
/// Used to refuse a destructive re-encrypt when the decrypting key may be wrong.
bool looksLikeVideoContainer(List<int> head) {
  if (head.length < 12) return false;

  // 1. ISO base media (mp4, m4v, mov, 3gp): bytes 4..7 equal ASCII 'f','t','y','p'
  if (head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70) {
    return true;
  }

  // 2. Matroska / WebM: bytes 0..3 equal 0x1A, 0x45, 0xDF, 0xA3
  if (head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3) {
    return true;
  }

  // 3. AVI: bytes 0..3 equal 'R','I','F','F' AND bytes 8..11 equal 'A','V','I',' '
  if (head[0] == 0x52 && head[1] == 0x49 && head[2] == 0x46 && head[3] == 0x46 &&
      head[8] == 0x41 && head[9] == 0x56 && head[10] == 0x49 && head[11] == 0x20) {
    return true;
  }

  // 4. QuickTime with a leading 'moov'/'mdat'/'free'/'wide'/'skip' box: bytes 4..7 equal code
  final b4 = head[4], b5 = head[5], b6 = head[6], b7 = head[7];
  if (b4 == 0x6D && b5 == 0x6F && b6 == 0x6F && b7 == 0x76) return true; // moov
  if (b4 == 0x6D && b5 == 0x64 && b6 == 0x61 && b7 == 0x74) return true; // mdat
  if (b4 == 0x66 && b5 == 0x72 && b6 == 0x65 && b7 == 0x65) return true; // free
  if (b4 == 0x77 && b5 == 0x69 && b6 == 0x64 && b7 == 0x65) return true; // wide
  if (b4 == 0x73 && b5 == 0x6B && b6 == 0x69 && b7 == 0x70) return true; // skip

  return false;
}

/// The on-disk encryption format of a vault media blob, decided from its
/// first 8 bytes. This never decrypts anything and never needs the vault
/// to be unlocked.
enum MediaBlobFormat {
  /// MVKEYv1\0 — AES-CBC under the master vault key.
  cbcV1,
  /// MVKEYc1\0 — AES-CTR under the device-local system key. Not recoverable
  /// from the recovery phrase alone.
  ctrV1,
  /// MVKEYc2\0 — AES-CTR under the master vault key.
  ctrV2,
  /// No recognised magic header. Very old blobs that begin with a raw IV.
  legacyNoHeader,
}

/// Classifies a blob from its leading bytes. Fewer than 8 bytes, or any
/// unrecognised prefix, is reported as [MediaBlobFormat.legacyNoHeader].
MediaBlobFormat classifyMediaHeader(List<int> head) {
  if (head.length < 8) return MediaBlobFormat.legacyNoHeader;

  bool isV1 = true;
  bool isCtrV1 = true;
  bool isCtrV2 = true;

  for (int i = 0; i < 8; i++) {
    if (head[i] != kMediaMagicV1[i]) isV1 = false;
    if (head[i] != kMediaMagicCtrV1[i]) isCtrV1 = false;
    if (head[i] != kMediaMagicCtrV2[i]) isCtrV2 = false;
  }

  if (isCtrV2) return MediaBlobFormat.ctrV2;
  if (isCtrV1) return MediaBlobFormat.ctrV1;
  if (isV1) return MediaBlobFormat.cbcV1;

  return MediaBlobFormat.legacyNoHeader;
}
