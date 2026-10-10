// test/game/widgets/word_silhouette_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/services/word_silhouette_resolver.dart';
import 'package:mimic/game/widgets/word_silhouette_widget.dart';

void main() {
  group('WordSilhouetteResolver tests', () {
    test('resolves archetype by exact or partial word match', () {
      expect(WordSilhouetteResolver.resolve('Dagger'), WordSilhouetteType.dagger);
      expect(WordSilhouetteResolver.resolve('Knife'), WordSilhouetteType.dagger);
      expect(WordSilhouetteResolver.resolve('Poison'), WordSilhouetteType.poison);
      expect(WordSilhouetteResolver.resolve('Arsenic'), WordSilhouetteType.poison);
      expect(WordSilhouetteResolver.resolve('Grimoire'), WordSilhouetteType.grimoire);
      expect(WordSilhouetteResolver.resolve('Spellbook'), WordSilhouetteType.grimoire);
      expect(WordSilhouetteResolver.resolve('Aswang'), WordSilhouetteType.aswangWings);
      expect(WordSilhouetteResolver.resolve('Manananggal'), WordSilhouetteType.aswangWings);
      expect(WordSilhouetteResolver.resolve('Tikbalang'), WordSilhouetteType.beastClaws);
      expect(WordSilhouetteResolver.resolve('Werewolf'), WordSilhouetteType.beastClaws);
      expect(WordSilhouetteResolver.resolve('Ghost'), WordSilhouetteType.specter);
      expect(WordSilhouetteResolver.resolve('White Lady'), WordSilhouetteType.specter);
      expect(WordSilhouetteResolver.resolve('Cemetery'), WordSilhouetteType.graveyard);
      expect(WordSilhouetteResolver.resolve('Crypt'), WordSilhouetteType.coffin);
      expect(WordSilhouetteResolver.resolve('Chainsaw'), WordSilhouetteType.chainsaw);
    });

    test('falls back to category when word is unknown', () {
      expect(
        WordSilhouetteResolver.resolve('UnknownBuilding', category: 'Locations'),
        WordSilhouetteType.mansion,
      );
      expect(
        WordSilhouetteResolver.resolve('NamelessEntity', category: 'The Occult'),
        WordSilhouetteType.altar,
      );
      expect(
        WordSilhouetteResolver.resolve('UnknownFolklore', category: 'Folklore'),
        WordSilhouetteType.aswangWings,
      );
      expect(
        WordSilhouetteResolver.resolve('AlienObject', category: 'RandomUnknown'),
        WordSilhouetteType.generalHorror,
      );
    });
  });

  group('WordSilhouetteWidget tests', () {
    testWidgets('renders CustomPaint with correct size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: WordSilhouetteWidget(
                type: WordSilhouetteType.dagger,
                size: 80,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WordSilhouetteWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(WordSilhouetteWidget),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.constraints?.maxWidth, 80);
      expect(container.constraints?.maxHeight, 80);
    });

    testWidgets('factory fromWord resolves and paints correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: WordSilhouetteWidget.fromWord('Tikbalang', size: 90),
            ),
          ),
        ),
      );

      final widget = tester.widget<WordSilhouetteWidget>(find.byType(WordSilhouetteWidget));
      expect(widget.type, WordSilhouetteType.beastClaws);
      expect(widget.size, 90);
    });
  });
}
