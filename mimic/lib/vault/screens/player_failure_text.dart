// lib/vault/screens/player_failure_text.dart
//
// H16: the fate of one play attempt, decided by the typed conversion outcome
// from `ensureVideoStreamable`. A refusal or an abort is reported in plain
// words instead of looking like an endless spinner.
//
// Pure-Dart home for the player-screen failure mapping and both screens' plain
// words. It lives here — not on either widget — so the pure unit tests can
// import it without dragging in the widget/plugin chain (video_player,
// chewie, Riverpod), which stalled the test load at +0 on this machine.
import '../services/video_vault_service.dart';

/// The fate of one play attempt, decided by the typed conversion outcome from
/// `ensureVideoStreamable` (register items H16/F4). A refusal or an abort is
/// reported in plain words instead of looking like an endless spinner.
enum PlayerOpenFailure {
  none,
  refusedNotAContainer,
  vaultLocked,
  missing,
  io,
  unknown,
}

/// Maps a typed conversion outcome to the player-screen failure it becomes.
/// Missing-file is detected here (not in the service) because the service
/// records it as [VideoMigrationFailure.io] at stage [VideoMigrationStage.precheck].
PlayerOpenFailure playerFailureFor(
  VideoMigrationOutcome outcome, {
  required bool playerReady,
}) {
  if (playerReady) return PlayerOpenFailure.none;
  switch (outcome.failure) {
    case VideoMigrationFailure.none:
      return PlayerOpenFailure.none;
    case VideoMigrationFailure.refusedNotAContainer:
      return PlayerOpenFailure.refusedNotAContainer;
    case VideoMigrationFailure.vaultLocked:
      return PlayerOpenFailure.vaultLocked;
    case VideoMigrationFailure.io:
      if (outcome.failedAt == VideoMigrationStage.precheck) {
        return PlayerOpenFailure.missing;
      }
      return PlayerOpenFailure.io;
    case VideoMigrationFailure.unknown:
      return PlayerOpenFailure.unknown;
  }
}

/// Plain-words line for each failure. Path-free by construction: the outcome
/// detail is never shown, only the kind.
String playerFailureMessage(PlayerOpenFailure failure, String? detailForLog) {
  // detailForLog is accepted so callers can debugPrint it; it is never shown.
  switch (failure) {
    case PlayerOpenFailure.none:
      return '';
    case PlayerOpenFailure.refusedNotAContainer:
      return 'This video cannot be played on this phone. The original was kept unchanged.';
    case PlayerOpenFailure.vaultLocked:
      return 'The vault locked during conversion. Unlock and try again.';
    case PlayerOpenFailure.missing:
      return 'This video file is missing from the vault.';
    case PlayerOpenFailure.io:
      return 'This video could not be read. Please try again.';
    case PlayerOpenFailure.unknown:
      return 'This video could not be prepared. Please try again.';
  }
}

/// The last conversion result, in plain words, for the Diagnostics screen
/// (register item H16: the 3G-0 baseline proved conversions persist, so this
/// is evidence, not a live progress line — no polling, no streams).
String describeMigrationOutcome(VideoMigrationOutcome? outcome) {
  if (outcome == null) return 'No conversion has run yet this session.';
  final took = (outcome.durationMs / 1000).toStringAsFixed(1);
  switch (outcome.failure) {
    case VideoMigrationFailure.none:
      if (outcome.sourceKind == 'already-c2') {
        return 'Last video was already in seekable format — no conversion needed.';
      }
      return 'Last conversion succeeded in ${took}s '
          '(${outcome.plaintextBytes} bytes).';
    case VideoMigrationFailure.refusedNotAContainer:
      return 'Last conversion refused: the file did not look like a video, '
          'so the original was kept unchanged.';
    case VideoMigrationFailure.vaultLocked:
      return 'Last conversion stopped: the vault locked while it was running.';
    case VideoMigrationFailure.io:
      return 'Last conversion failed: the file could not be read or written.';
    case VideoMigrationFailure.unknown:
      return 'Last conversion failed '
          '(${outcome.detail ?? outcome.failedAt?.name ?? 'unknown'}).';
  }
}