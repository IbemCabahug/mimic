// test/vault/widgets/tag_caption_editor_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/widgets/tag_caption_editor_sheet.dart';

void main() {
  testWidgets('showTagCaptionEditorSheet renders initial tags and caption, and saves edits',
      (tester) async {
    List<String>? savedTags;
    String? savedCaption;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showTagCaptionEditorSheet(
                  context: context,
                  title: 'Tax Document',
                  initialTags: ['#Tax'],
                  initialCaption: '2025 W2 form',
                  onSave: (tags, caption) async {
                    savedTags = tags;
                    savedCaption = caption;
                  },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Tax Document'), findsOneWidget);
    expect(find.text('#Tax'), findsWidgets);
    expect(find.text('2025 W2 form'), findsOneWidget);

    // Tap preset chip '#Important'
    await tester.tap(find.text('#Important'));
    await tester.pumpAndSettle();

    // Type a custom tag
    await tester.enterText(find.byType(TextField).last, 'Quarterly');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Edit caption
    await tester.enterText(find.byType(TextField).first, 'Updated W2 form');
    await tester.pumpAndSettle();

    // Tap Save
    final saveButton = find.text('Save Encrypted Details');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedTags, isNotNull);
    expect(savedTags, contains('#Tax'));
    expect(savedTags, contains('#Important'));
    expect(savedTags, contains('#Quarterly'));
    expect(savedCaption, 'Updated W2 form');
  });

  testWidgets('showTagCaptionEditorSheet hides caption when showCaptionField is false',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showTagCaptionEditorSheet(
                  context: context,
                  title: 'Private Note',
                  initialTags: ['#Personal'],
                  showCaptionField: false,
                  onSave: (tags, caption) async {},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Private Note'), findsOneWidget);
    expect(find.text('Private Caption / Note'), findsNothing);
  });
}
