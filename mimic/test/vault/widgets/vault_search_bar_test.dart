// test/vault/widgets/vault_search_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/widgets/vault_search_bar.dart';

void main() {
  testWidgets('VaultSearchBar renders search field and responds to text changes',
      (tester) async {
    final controller = TextEditingController();
    String query = '';
    var clearCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultSearchBar(
            controller: controller,
            hintText: 'Search test items...',
            onQueryChanged: (v) => query = v,
            onClear: () => clearCalled = true,
            selectedTag: null,
            onTagSelected: (_) {},
            onProRequired: () {},
          ),
        ),
      ),
    );

    expect(find.text('Search test items...'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'passport');
    expect(query, 'passport');

    await tester.pump();
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    expect(clearCalled, isTrue);
  });

  testWidgets('VaultSearchBar gates tags for non-Pro users', (tester) async {
    final controller = TextEditingController();
    var proRequiredCalled = false;
    String? selectedTag;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultSearchBar(
            controller: controller,
            onQueryChanged: (_) {},
            onClear: () {},
            selectedTag: selectedTag,
            onTagSelected: (t) => selectedTag = t,
            availableTags: const ['#Secret'],
            isPro: false,
            onProRequired: () => proRequiredCalled = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await tester.tap(find.text('#Secret'));
    await tester.pump();

    expect(proRequiredCalled, isTrue);
    expect(selectedTag, isNull);
  });

  testWidgets('VaultSearchBar allows selecting tags for Pro users', (tester) async {
    final controller = TextEditingController();
    var proRequiredCalled = false;
    String? selectedTag;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultSearchBar(
            controller: controller,
            onQueryChanged: (_) {},
            onClear: () {},
            selectedTag: selectedTag,
            onTagSelected: (t) => selectedTag = t,
            availableTags: const ['#ID'],
            isPro: true,
            onProRequired: () => proRequiredCalled = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsNothing);

    await tester.tap(find.text('#ID'));
    await tester.pump();

    expect(proRequiredCalled, isFalse);
    expect(selectedTag, '#ID');
  });

  testWidgets('VaultSearchBar renders optional trailing widget', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultSearchBar(
            controller: controller,
            onQueryChanged: (_) {},
            onClear: () {},
            selectedTag: null,
            onTagSelected: (_) {},
            onProRequired: () {},
            trailing: const Icon(Icons.sort, key: Key('sort_icon')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('sort_icon')), findsOneWidget);
  });
}
