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
}
