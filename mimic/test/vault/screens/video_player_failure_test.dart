// H16: the fate of one play attempt lives in player_failure_text.dart —
// a pure-Dart home outside the widget files, so the unit test imports it
// without the widget/plugin chain.
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/screens/player_failure_text.dart';
import 'package:mimic/vault/services/video_vault_service.dart';

VideoMigrationOutcome outcome({
  required VideoMigrationFailure failure,
  VideoMigrationStage? failedAt,
  String sourceKind = 'v1',
  bool converted = false,
  String? detail,
  int plaintextBytes = 0,
  int durationMs = 0,
}) =>
    VideoMigrationOutcome(
      videoId: 'vid',
      sourceKind: sourceKind,
      converted: converted,
      failure: failure,
      failedAt: failedAt,
      detail: detail,
      plaintextBytes: plaintextBytes,
      durationMs: durationMs,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('3G-1C player open failure mapping (H16/F4)', () {
    test('U1 — success outcome maps to none when the player is ready', () {
      final failure = playerFailureFor(
        outcome(
            failure: VideoMigrationFailure.none,
            sourceKind: 'already-c2',
            converted: true),
        playerReady: true,
      );
      expect(failure, PlayerOpenFailure.none);
    });

    test('U2 — refused container maps to refusedNotAContainer with plain words', () {
      final failure = playerFailureFor(
        outcome(
            failure: VideoMigrationFailure.refusedNotAContainer,
            failedAt: VideoMigrationStage.containerGate,
            detail: 'refused at container gate'),
        playerReady: false,
      );
      expect(failure, PlayerOpenFailure.refusedNotAContainer);
      final message = playerFailureMessage(failure, 'refused at container gate');
      expect(message, contains('kept unchanged'));
      expect(message, isNot(contains('refused at container gate')),
          reason: 'the path-free detail must never reach the screen');
    });

    test('U3 — vaultLocked maps to vaultLocked', () {
      final failure = playerFailureFor(
        outcome(
            failure: VideoMigrationFailure.vaultLocked,
            failedAt: VideoMigrationStage.decrypt),
        playerReady: false,
      );
      expect(failure, PlayerOpenFailure.vaultLocked);
      expect(playerFailureMessage(failure, null), contains('locked'));
    });

    test('U4 — io at precheck maps to missing, io elsewhere maps to io', () {
      expect(
        playerFailureFor(
          outcome(
              failure: VideoMigrationFailure.io,
              failedAt: VideoMigrationStage.precheck),
          playerReady: false,
        ),
        PlayerOpenFailure.missing,
      );
      expect(
        playerFailureFor(
          outcome(
              failure: VideoMigrationFailure.io,
              failedAt: VideoMigrationStage.rename),
          playerReady: false,
        ),
        PlayerOpenFailure.io,
      );
      expect(playerFailureMessage(PlayerOpenFailure.missing, null),
          contains('missing'));
    });

    test('U5 — unknown maps to unknown with a retry line', () {
      final failure = playerFailureFor(
        outcome(
            failure: VideoMigrationFailure.unknown,
            failedAt: VideoMigrationStage.reencrypt,
            detail: 'Exception: boom'),
        playerReady: false,
      );
      expect(failure, PlayerOpenFailure.unknown);
      final message = playerFailureMessage(failure, 'Exception: boom');
      expect(message, contains('try again'));
      expect(message, isNot(contains('boom')));
    });

    test('U6 — ready player swallows even a failure outcome (no false error)', () {
      final failure = playerFailureFor(
        outcome(failure: VideoMigrationFailure.io),
        playerReady: true,
      );
      expect(failure, PlayerOpenFailure.none);
    });
  });

  group('3G-1C diagnostics last-conversion line (H16)', () {
    test('U7 — null outcome says no conversion has run', () {
      expect(describeMigrationOutcome(null), contains('No conversion'));
    });

    test('U8 — already-c2 says no conversion was needed', () {
      expect(
        describeMigrationOutcome(outcome(
            failure: VideoMigrationFailure.none,
            sourceKind: 'already-c2',
            converted: true)),
        contains('already in seekable format'),
      );
    });

    test('U9 — every failure kind has a plain-words line', () {
      expect(
        describeMigrationOutcome(outcome(
            failure: VideoMigrationFailure.refusedNotAContainer,
            failedAt: VideoMigrationStage.containerGate)),
        contains('kept unchanged'),
      );
      expect(
        describeMigrationOutcome(outcome(
            failure: VideoMigrationFailure.vaultLocked,
            failedAt: VideoMigrationStage.decrypt)),
        contains('locked'),
      );
      expect(
        describeMigrationOutcome(
            outcome(failure: VideoMigrationFailure.io, failedAt: VideoMigrationStage.rename)),
        contains('could not be read'),
      );
    });
  });
}
