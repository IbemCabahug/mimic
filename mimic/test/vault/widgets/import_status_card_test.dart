// test/vault/widgets/import_status_card_test.dart
//
// The live import card is the frontend sign the owner asked for: before it,
// a 2:34 video encrypted with nothing on screen until the system delete
// dialog appeared. These tests pin the visible contract so a refactor cannot
// quietly re-hide it: an empty session draws nothing, a working session lists
// every chosen file (named rows + the 1/N header), a settled batch reports
// per-row outcomes, and a big batch scrolls inside the card instead of
// pushing the grid off screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/import_progress.dart';
import 'package:mimic/vault/widgets/import_status_card.dart';

Widget _wrap(ImportSession session) =>
    MaterialApp(home: Scaffold(body: ImportStatusCard(session: session)));

void main() {
  testWidgets('an empty session draws nothing', (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(_wrap(session));

    expect(find.byType(Container), findsNothing);
    expect(find.textContaining('Importing'), findsNothing);
    expect(find.textContaining('Import finished'), findsNothing);
  });

  testWidgets('a working batch lists every chosen file, not just the count',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const []);
    // The picker reported 3 chosen items before file 1 started.
    session.setTotal(3);
    session.ensureSlot(0, 'a.mp4');
    session.markEncrypting(0, 1);
    await tester.pumpWidget(_wrap(session));

    // The header counts the whole batch from the first frame.
    expect(find.text('Importing 1/3 ...'), findsOneWidget);
    // Every file has a row the moment it is known, so the user sees the queue.
    expect(find.text('a.mp4'), findsOneWidget);
    expect(find.text('Encrypting'), findsOneWidget);
    expect(find.text('Queued'), findsNWidgets(2));
    // One spinner for the header, one for the row in flight.
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('the delete-confirmation wait is named while the OS dialog is up',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['b.mp4']);
    session.markEncrypting(0, 1);
    await tester.pumpWidget(_wrap(session));

    expect(find.text('Encrypting'), findsOneWidget);
    expect(find.text('Waiting for delete confirmation'), findsNothing);

    // The dialog is up: the row must say so, and the batch is still working.
    session.markWaitingDeleteConfirm();
    await tester.pump();
    expect(find.text('Waiting for delete confirmation'), findsOneWidget);
    expect(find.text('Importing 1/1 ...'), findsOneWidget);
    expect(session.isWorking, isTrue);
  });

  testWidgets('a settled batch reports per-row outcomes and any failures',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['a.mp4', 'b.mp4', 'c.mp4']);
    session.markSaved(0);
    // The owner denied the OS delete dialog (or the platform refused), so the
    // row must not claim a clean 'Saved'.
    session.markSavedOriginalKept(1);
    session.markFailed(2, 'Not imported');
    await tester.pumpWidget(_wrap(session));

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved, original kept'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    // The failure detail is shown, so "Failed" is actionable rather than blind.
    expect(find.text('Not imported'), findsOneWidget);
    // 1 of 3 did not make it: the header must not claim a clean finish.
    expect(find.text('Import finished — 1 not imported'), findsOneWidget);
    expect(session.isWorking, isFalse);
  });

  testWidgets('a big batch scrolls inside the card instead of eating the grid',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const []);
    session.setTotal(12);
    for (var i = 0; i < 12; i++) {
      session.ensureSlot(i, 'clip_$i.mp4');
      session.markSaved(i);
    }
    await tester.pumpWidget(_wrap(session));

    expect(find.text('clip_11.mp4'), findsOneWidget);
    expect(find.text('Import finished (12/12)'), findsOneWidget);
    // Rows are clipped to a scroll viewport, so a 12-file batch cannot push
    // the vault grid off the screen.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(ImportStatusCard)).height, lessThan(200));
  });
}
