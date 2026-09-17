// test/vault/widgets/import_activity_button_test.dart
//
// F4 rework (2026-09-17). The above-grid card was replaced by a compact
// labelled pill above the + FAB plus an on-demand detail sheet, because the
// always-expanded card ate grid space during large batches. The card's own
// tests (import_status_card_test.dart) still cover the row helpers, but the
// pill is now the surface the owner actually sees, so it needs its own
// contract pinned:
//  - an idle session draws NOTHING, so no dead control sits above the FAB;
//  - a working batch carries WORDS and live counts ("Importing 2/3"), not a
//    bare spinner an unfamiliar user has to interpret (recognition over
//    recall);
//  - the touch target stays >= 44px so the secondary control is operable;
//  - a settled batch reports its outcome;
//  - the words never say "upload" — nothing leaves the device;
//  - opening the sheet is an inspection, not a commitment: closing it must
//    not clear or cancel the import (dismissing a view is not cancelling work).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/import_progress.dart';
import 'package:mimic/vault/widgets/import_activity_button.dart';

Widget _wrap(ImportSession session) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ImportActivityButton(
            key: const ValueKey('import_activity_button'),
            session: session,
            onTap: () => showImportDetailsSheet(context, session),
          ),
        ),
      ),
    );

/// Three chosen files, one saved, the second in flight, the third still queued.
ImportSession _midBatch() {
  final session = ImportSession();
  session.begin(const ['a.mp4', 'b.mp4', 'c.mp4']);
  session.markEncrypting(0, 1);
  session.markSaved(0);
  session.markEncrypting(1, 2);
  return session;
}

/// Opens the detail sheet and lets its slide-in finish.
///
/// pumpAndSettle is unusable while a batch is working: the pill's
/// CircularProgressIndicator animates forever, so the tree never becomes
/// quiescent and pumpAndSettle times out. Advancing a fixed slice is enough
/// to complete the modal route's entrance animation.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('import_activity_button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('an idle session draws no pill at all', (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(_wrap(session));

    // Nothing to tap and nothing to read: no dead control above the + FAB.
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(Container), findsNothing);
    expect(find.textContaining('Import'), findsNothing);
  });

  testWidgets('a working batch is labelled with live counts, not just a spinner',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['a.mp4', 'b.mp4', 'c.mp4']);
    session.markEncrypting(1, 2);
    await tester.pumpWidget(_wrap(session));

    // The whole batch is counted from the first frame: 2 of 3, not 1 of 1.
    expect(find.text('Importing 2/3'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the pill keeps a comfortable touch target', (tester) async {
    final session = _midBatch();
    addTearDown(session.dispose);
    await tester.pumpWidget(_wrap(session));

    expect(tester.getSize(find.byType(ImportActivityButton)).height,
        greaterThanOrEqualTo(44));
  });


  testWidgets('a settled batch reports completion', (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['a.mp4', 'b.mp4', 'c.mp4']);
    session.markSaved(0);
    session.markSaved(1);
    session.markSaved(2);
    await tester.pumpWidget(_wrap(session));

    expect(find.text('Import finished (3/3)'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a settled batch with a failure says how many did not arrive',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['a.mp4', 'bad.mp4']);
    session.markSaved(0);
    session.markFailed(1, 'Could not read file');
    await tester.pumpWidget(_wrap(session));

    // Honest arithmetic: one of the two files is not in the vault.
    expect(find.text('Import finished — 1 not imported'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('the words never say "upload" — nothing leaves the device',
      (tester) async {
    final session = _midBatch();
    addTearDown(session.dispose);
    await tester.pumpWidget(_wrap(session));
    expect(find.textContaining('pload'), findsNothing);

    await _openSheet(tester);
    expect(find.textContaining('pload'), findsNothing);
  });

  testWidgets('the sheet lists every chosen file with its live status',
      (tester) async {
    final session = _midBatch();
    addTearDown(session.dispose);
    session.markFailed(2, 'Could not read file');
    await tester.pumpWidget(_wrap(session));

    await _openSheet(tester);

    // The header counts the batch; every name is inspectable on demand.
    expect(find.text('Importing 2/3 ...'), findsOneWidget);
    expect(find.text('a.mp4'), findsOneWidget);
    expect(find.text('b.mp4'), findsOneWidget);
    expect(find.text('c.mp4'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Encrypting'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    // The failure reason travels with the row instead of only a red word.
    expect(find.text('Could not read file'), findsOneWidget);
  });

  testWidgets('the delete-confirmation wait is named while the OS dialog is up',
      (tester) async {
    final session = ImportSession();
    addTearDown(session.dispose);
    session.begin(const ['a.mp4']);
    session.markEncrypting(0, 1);
    session.markWaitingDeleteConfirm();
    await tester.pumpWidget(_wrap(session));

    await _openSheet(tester);

    expect(find.text('Waiting for delete confirmation'), findsOneWidget);
  });

  testWidgets('closing the sheet does not cancel or clear the import',
      (tester) async {
    final session = _midBatch();
    addTearDown(session.dispose);
    await tester.pumpWidget(_wrap(session));

    await _openSheet(tester);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The sheet is gone, the work is not: same rows, same live counts.
    expect(find.text('Close'), findsNothing);
    expect(session.files.length, 3);
    expect(session.isWorking, isTrue);
    expect(find.text('Importing 2/3'), findsOneWidget);
  });
}