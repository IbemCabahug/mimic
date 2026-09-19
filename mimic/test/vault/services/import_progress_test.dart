// test/vault/services/import_progress_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/import_progress.dart';

void main() {
  test('setTotal queues the whole batch, then the per-file walk settles it', () {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const []);
    expect(session.isActive, isFalse);

    // The picker reported 3 chosen items: all 3 rows exist as Queued straight
    // away, so the header reads 1/3 from the first frame instead of growing
    // 1/1 -> 2/2 -> 3/3 as each file starts.
    session.setTotal(3);
    expect(session.total, 3);
    expect(session.position, 1);
    expect(session.isActive, isTrue);
    expect(session.isWorking, isTrue, reason: 'Queued rows are still work');
    expect(session.files.every((f) => f.status == ImportFileStatus.queued), isTrue);

    // File 1 starts: its row is named and encrypting, files 2 and 3 stay queued.
    session.ensureSlot(0, 'a.mp4');
    session.markEncrypting(0, 1);
    expect(session.files[0].name, 'a.mp4');
    expect(session.files[0].status, ImportFileStatus.encrypting);
    expect(session.files[2].status, ImportFileStatus.queued);

    // The OS delete-confirmation dialog has no completion callback of its own,
    // so this state owns the whole wait (dialog + the delete pass after Allow).
    session.markWaitingDeleteConfirm();
    expect(session.files[0].status, ImportFileStatus.waitingDeleteConfirm);
    expect(session.isWorking, isTrue);

    session.markSaved(0);
    session.markSavedOriginalKept(1);
    session.markFailed(2, 'Not imported');
    expect(session.isWorking, isFalse, reason: 'Settled rows stop the spinner');
    expect(session.files[2].detail, 'Not imported');

    expect(importFileStatusLabel(ImportFileStatus.queued), 'Queued');
    expect(importFileStatusLabel(ImportFileStatus.encrypting), 'Encrypting');
    expect(importFileStatusLabel(ImportFileStatus.waitingDeleteConfirm),
        'Waiting for delete confirmation');
    expect(importFileStatusLabel(ImportFileStatus.saved), 'Saved');
    expect(importFileStatusLabel(ImportFileStatus.savedOriginalKept),
        'Saved, original kept');
    expect(importFileStatusLabel(ImportFileStatus.failed), 'Failed');

    session.clear();
    expect(session.isActive, isFalse);
  });

  test('failed rows carry the detail and stay active for the linger window', () {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.ensureSlot(1, 'b.mp4');
    expect(session.total, 2);
    session.markFailed(1, 'boom');
    expect(session.files[1].status, ImportFileStatus.failed);
    expect(session.files[1].detail, 'boom');
    expect(session.isActive, isTrue);
    session.markSavedOriginalKept(0);
    expect(session.files[0].status, ImportFileStatus.savedOriginalKept);
  });

  group('restore sessions (video vault, 2026-09-18)', () {
    test('beginRestore switches the verb and every row is born Restoring', () {
      final session = ImportSession();
      addTearDown(session.dispose);
      session.beginRestore(const ['clip.mp4', 'trip.mp4']);

      expect(session.verb, 'Restoring');
      expect(session.total, 2);
      expect(session.position, 1);
      expect(session.isWorking, isTrue,
          reason: 'a restoring row is work, exactly like an encrypting row');
      expect(session.files.every((f) => f.status == ImportFileStatus.restoring),
          isTrue);
      expect(
          importFileStatusLabel(ImportFileStatus.restoring), 'Restoring');

      // Import wording must not leak into a restore session.
      session.begin(const ['x.jpg']);
      expect(session.verb, 'Importing');
      session.clear();
      expect(session.verb, 'Importing',
          reason: 'clear resets the verb for the next session');
    });

    test('updateProgress clamps to 0..1 and null means the unmeasurable phase',
        () {
      final session = ImportSession();
      addTearDown(session.dispose);
      session.beginRestore(const ['clip.mp4']);

      var notifications = 0;
      session.addListener(() => notifications++);

      session.markRestoring(0, 1);
      session.updateProgress(0, 0.45);
      expect(session.files[0].progress, 0.45);
      expect(session.isWorking, isTrue);

      // Out-of-range percents are clamped, never thrown, so a fast poll
      // racing the file length can never crash the flow.
      session.updateProgress(0, 1.5);
      expect(session.files[0].progress, 1.0);
      session.updateProgress(0, -0.2);
      expect(session.files[0].progress, 0.0);

      // null = the gallery-write phase: work under way, percent unknown.
      session.updateProgress(0, null);
      expect(session.files[0].progress, isNull);
      expect(session.isWorking, isTrue,
          reason: 'the unmeasurable save phase is still work');

      // Out-of-range indices are ignored, not crashes: the screen cannot
      // outlive its session rows.
      session.updateProgress(7, 0.5);
      expect(notifications, greaterThan(0));
    });

    test('markSaved settles the row and keeps the percent for the sheet', () {
      final session = ImportSession();
      addTearDown(session.dispose);
      session.beginRestore(const ['clip.mp4']);
      session.markRestoring(0, 1);
      session.updateProgress(0, 0.9);

      session.markSaved(0);
      expect(session.isWorking, isFalse);
      expect(session.files[0].status, ImportFileStatus.saved);
      expect(session.isActive, isTrue,
          reason: 'the settled session lingers ~4s so the outcome is seen');
      session.clear();
      expect(session.isActive, isFalse);
    });

    test('requestCancel sets the flag once and begin/beginRestore/clear reset it', () {
      final session = ImportSession();
      addTearDown(session.dispose);
      var notifications = 0;
      session.addListener(() => notifications++);

      session.begin(const ['a.jpg']);
      session.requestCancel();
      session.requestCancel(); // idempotent: one request is one notification
      expect(session.cancelRequested, isTrue);
      expect(notifications, 2,
          reason: 'one for begin, one for the FIRST cancel — a repeat is silent');

      // A new flow always starts cancellable-clean.
      session.beginRestore(const ['b.mp4']);
      expect(session.cancelRequested, isFalse);
      session.requestCancel();
      session.clear();
      expect(session.cancelRequested, isFalse);
    });

    test('markCancelled labels the row Cancelled and settles it', () {
      final session = ImportSession();
      addTearDown(session.dispose);
      session.begin(const ['a.jpg', 'b.jpg']);
      session.markEncrypting(0, 1);

      session.requestCancel();
      // The screen's finalization sweep: rows the cancelled loop never
      // reached become Cancelled — never Failed.
      session.markCancelled(1);
      expect(session.files[1].status, ImportFileStatus.cancelled);
      expect(importFileStatusLabel(ImportFileStatus.cancelled), 'Cancelled');
      expect(session.isWorking, isTrue,
          reason: 'row 0 is still encrypting — the in-flight file finishes');

      session.markSaved(0);
      expect(session.isWorking, isFalse,
          reason: 'cancelled rows are DONE rows; the pill can settle');
    });
  });
}
