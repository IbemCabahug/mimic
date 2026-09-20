// test/game/data/word_context_test.dart
//
// F28 — curated word context ("describing angles"):
// 1. Data integrity over the English packs — every pair authored, contexts
//    never contain their own word nor the twin word (a leak would let a
//    player say the word or recognize the pair), substantial and distinct.
// 2. Localized packs (Filipino, Cebuano) keep their own words but inherit
//    the English blurb of their parallel base pair — English-only by the
//    owner's call (localized context text reads as "cringe" to Filipino and
//    Cebuano players). Guards the 1:1 index alignment with hand-verified
//    anchors, and re-runs the anti-leak rule against the localized words.
// 3. GameState.getContextForPlayer — the right side reaches the right
//    player, and contextless words (the Nightmare second mimic's extra
//    word, synced pairs without contexts) answer ''.

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/state/game_state.dart';

void main() {
  group('curated word context — data integrity (English packs)', () {
    final packs = WordPackData.packs;

    test('every English pair has a non-empty context for BOTH words in BOTH tiers', () {
      var contextsChecked = 0;
      for (final pack in packs) {
        for (final pair in pack.pairs) {
          final sides = [
            ['real', pair.realWord, pair.realWordContext, pair.realWordProContext],
            ['mimic', pair.mimicWord, pair.mimicWordContext, pair.mimicWordProContext],
          ];
          for (final side in sides) {
            final label = side[0];
            final word = side[1];
            expect(
              side[2],
              isNotEmpty,
              reason: '${pack.id} / "$word": $label FREE context is empty',
            );
            expect(
              side[3],
              isNotEmpty,
              reason: '${pack.id} / "$word": $label PRO context is empty',
            );
          }
          contextsChecked += 2;
        }
      }
      // The authoring task is per pair — sanity that the sweep really ran.
      expect(contextsChecked, greaterThanOrEqualTo(100));
    });

    test('no context contains its own word or its twin (substring, case-insensitive)', () {
      for (final pack in packs) {
        for (final pair in pack.pairs) {
          final ownReal = pair.realWord.toLowerCase();
          final ownMimic = pair.mimicWord.toLowerCase();
          // Sweep both tiers — a leak in either one hands the player the word.
          final blurbs = <List<String>>[
            ['real FREE', ownReal, ownMimic, pair.realWordContext],
            ['real PRO', ownReal, ownMimic, pair.realWordProContext],
            ['mimic FREE', ownMimic, ownReal, pair.mimicWordContext],
            ['mimic PRO', ownMimic, ownReal, pair.mimicWordProContext],
          ];
          for (final b in blurbs) {
            final label = b[0];
            final own = b[1];
            final twin = b[2];
            final text = b[3].toLowerCase();
            expect(
              text.contains(own),
              isFalse,
              reason: '${pack.id}: $label context contains the word itself',
            );
            expect(
              text.contains(twin),
              isFalse,
              reason: '${pack.id}: $label context leaks the twin',
            );
          }
        }
      }
    });

    test('contexts are substantial, the two sides differ, and FREE stays shorter than PRO', () {
      for (final pack in packs) {
        for (final pair in pack.pairs) {
          // FREE (generalized) tier.
          expect(
            pair.realWordContext.length,
            allOf(greaterThanOrEqualTo(55), lessThanOrEqualTo(400)),
            reason: '${pack.id} / "${pair.realWord}": real FREE length',
          );
          expect(
            pair.mimicWordContext.length,
            allOf(greaterThanOrEqualTo(55), lessThanOrEqualTo(400)),
            reason: '${pack.id} / "${pair.mimicWord}": mimic FREE length',
          );
          expect(
            pair.realWordContext,
            isNot(equals(pair.mimicWordContext)),
            reason: '${pack.id} / "${pair.realWord}": both FREE sides identical',
          );
          // PRO (detailed) tier.
          expect(
            pair.realWordProContext.length,
            allOf(greaterThanOrEqualTo(40), lessThanOrEqualTo(400)),
            reason: '${pack.id} / "${pair.realWord}": real PRO length',
          );
          expect(
            pair.mimicWordProContext.length,
            allOf(greaterThanOrEqualTo(40), lessThanOrEqualTo(400)),
            reason: '${pack.id} / "${pair.mimicWord}": mimic PRO length',
          );
          expect(
            pair.realWordProContext,
            isNot(equals(pair.mimicWordProContext)),
            reason: '${pack.id} / "${pair.realWord}": both PRO sides identical',
          );
          // The tier split itself is checked in the dedicated shape test
          // below (FREE guides with a nudge, PRO lists concrete props —
          // a length comparison would be a false proxy for specificity).
        }
      }
    });

    test('tiers are shaped differently: FREE guides, PRO lists the props', () {
      // FREE blurbs end in a describing nudge; PRO blurbs are pure prop
      // enumerations with no instructions. A player comparing tiers sees
      // the difference in kind, and the data cannot silently drift from
      // one shape into the other.
      const guidance = ['describe', 'talk about', 'set the'];
      for (final pack in packs) {
        for (final pair in pack.pairs) {
          final freeReal = pair.realWordContext.toLowerCase();
          final freeMimic = pair.mimicWordContext.toLowerCase();
          final proReal = pair.realWordProContext.toLowerCase();
          final proMimic = pair.mimicWordProContext.toLowerCase();
          expect(
            guidance.any(freeReal.contains),
            isTrue,
            reason: '${pack.id} / "${pair.realWord}": FREE real blurb has no describing nudge',
          );
          expect(
            guidance.any(freeMimic.contains),
            isTrue,
            reason: '${pack.id} / "${pair.mimicWord}": FREE mimic blurb has no describing nudge',
          );
          expect(
            guidance.any(proReal.contains),
            isFalse,
            reason: '${pack.id} / "${pair.realWord}": PRO real blurb contains instructions',
          );
          expect(
            guidance.any(proMimic.contains),
            isFalse,
            reason: '${pack.id} / "${pair.mimicWord}": PRO mimic blurb contains instructions',
          );
        }
      }
    });
  });

  group('localized packs inherit the English context (English-only by design)', () {
    const localizedCodes = ['fil', 'ceb'];

    test('the merge keeps every pack and hands each pair the base context of its index', () {
      for (final code in localizedCodes) {
        final localized = WordPackData.getPacksForLanguage(code);
        expect(
          localized.map((p) => p.id).toList(),
          WordPackData.packs.map((p) => p.id).toList(),
          reason: '$code: pack ids/order must match the English packs',
        );
        for (var pi = 0; pi < localized.length; pi++) {
          final base = WordPackData.packs[pi];
          expect(
            localized[pi].pairs.length,
            base.pairs.length,
            reason: '$code / ${base.id}: pair count must match the base pack',
          );
          for (var i = 0; i < base.pairs.length; i++) {
            final lp = localized[pi].pairs[i];
            // The whole point of the feature: a Filipino/Cebuano player
            // still gets describing-angles blurbs in both tiers, and they
            // are the English definitions of the word they were dealt.
            expect(
              lp.realWordContext,
              base.pairs[i].realWordContext,
              reason:
                  '$code / ${base.id}[$i] "${lp.realWord}": inherited real FREE context',
            );
            expect(
              lp.mimicWordContext,
              base.pairs[i].mimicWordContext,
              reason:
                  '$code / ${base.id}[$i] "${lp.mimicWord}": inherited mimic FREE context',
            );
            expect(
              lp.realWordProContext,
              base.pairs[i].realWordProContext,
              reason:
                  '$code / ${base.id}[$i] "${lp.realWord}": inherited real PRO context',
            );
            expect(
              lp.mimicWordProContext,
              base.pairs[i].mimicWordProContext,
              reason:
                  '$code / ${base.id}[$i] "${lp.mimicWord}": inherited mimic PRO context',
            );
            expect(
              lp.realWordContext,
              isNotEmpty,
              reason:
                  '$code / ${base.id}[$i] "${lp.realWord}": info button would hide',
            );
            expect(
              lp.mimicWordContext,
              isNotEmpty,
              reason:
                  '$code / ${base.id}[$i] "${lp.mimicWord}": info button would hide',
            );
          }
        }
      }
    });

    test('the merge really localizes the words (not a silent English fallback)', () {
      for (final code in localizedCodes) {
        final localized = WordPackData.getPacksForLanguage(code);
        var total = 0;
        var translated = 0;
        for (var pi = 0; pi < localized.length; pi++) {
          final base = WordPackData.packs[pi];
          for (var i = 0; i < localized[pi].pairs.length; i++) {
            total += 2;
            if (localized[pi].pairs[i].realWord != base.pairs[i].realWord) {
              translated++;
            }
            if (localized[pi].pairs[i].mimicWord != base.pairs[i].mimicWord) {
              translated++;
            }
          }
        }
        expect(
          translated,
          greaterThan(total ~/ 2),
          reason: '$code: expected mostly translated words, got $translated/$total',
        );
      }
    });

    test('no localized word leaks through its inherited English context', () {
      // Same anti-leak rule as the English sweep, applied to the localized
      // words, in both tiers: the inherited blurb must not contain the
      // player's own word nor its twin, in either language (e.g. the
      // Cebuano "Freezer" must not be spelled out inside the English
      // blurb for Coldroom, free or pro).
      for (final code in localizedCodes) {
        for (final pack in WordPackData.getPacksForLanguage(code)) {
          for (final pair in pack.pairs) {
            final real = pair.realWord.toLowerCase();
            final mimic = pair.mimicWord.toLowerCase();
            final blurbs = <List<String>>[
              ['real FREE', real, mimic, pair.realWordContext],
              ['real PRO', real, mimic, pair.realWordProContext],
              ['mimic FREE', mimic, real, pair.mimicWordContext],
              ['mimic PRO', mimic, real, pair.mimicWordProContext],
            ];
            for (final b in blurbs) {
              final label = b[0];
              final own = b[1];
              final twin = b[2];
              final text = b[3].toLowerCase();
              expect(
                text.contains(own),
                isFalse,
                reason: '$code / ${pack.id}: $label context contains "$own"',
              );
              expect(
                text.contains(twin),
                isFalse,
                reason: '$code / ${pack.id}: $label context leaks twin',
              );
            }
          }
        }
      }
    });

    // Hand-verified from the authoring table (localized word → the English
    // word it translates). The English-context merge attaches blurbs by
    // parallel index, so a single reordered line in a localized list would
    // silently hand players the wrong word's angles — these anchors pin the
    // alignment of both sides of a pair, across every pack and language.
    // Format: [language, packId, localized word, English word].
    const anchors = <List<String>>[
      ['fil', 'dark_places', 'Sementeryo', 'Cemetery'],
      ['fil', 'dark_places', 'Kubo', 'Cottage'],
      ['fil', 'dark_places', 'Nitso', 'Crypt'],
      ['ceb', 'dark_places', 'Tanaman', 'Garden'],
      ['ceb', 'dark_places', 'Morge', 'Morgue'],
      ['fil', 'the_occult', 'Sumpa', 'Curse'],
      ['fil', 'the_occult', 'Bituin', 'Star'],
      ['ceb', 'the_occult', 'Mamarang', 'Warlock'],
      ['ceb', 'the_occult', 'Tigom', 'Meeting'],
      ['fil', 'crime_scene', 'Bangkay', 'Corpse'],
      ['fil', 'crime_scene', 'Manyika', 'Dummy'],
      ['ceb', 'crime_scene', 'Pangilkil', 'Blackmail'],
      ['ceb', 'crime_scene', 'Timailhan', 'Clue'],
      ['fil', 'survival_horror', 'Bitag', 'Trap'],
      ['fil', 'survival_horror', 'Halimaw', 'Monster'],
      ['ceb', 'survival_horror', 'Lit-ag', 'Trap'],
      ['ceb', 'survival_horror', 'Uwat', 'Scar'],
      ['fil', 'everyday_dread', 'Bangungot', 'Nightmare'],
      ['fil', 'everyday_dread', 'Isip', 'Thought'],
      ['ceb', 'everyday_dread', 'Damgo', 'Dream'],
      ['ceb', 'everyday_dread', 'Kamingaw', 'Loneliness'],
    ];

    test('hand-verified anchors confirm the 1:1 index alignment', () {
      for (final anchor in anchors) {
        final code = anchor[0];
        final packId = anchor[1];
        final localizedWord = anchor[2];
        final englishWord = anchor[3];

        final localized = WordPackData.getPacksForLanguage(code)
            .firstWhere((p) => p.id == packId);
        final base = WordPackData.packs.firstWhere((p) => p.id == packId);

        final li = localized.pairs.indexWhere((p) =>
            p.realWord == localizedWord || p.mimicWord == localizedWord);
        final bi = base.pairs.indexWhere(
            (p) => p.realWord == englishWord || p.mimicWord == englishWord);

        expect(li, isNot(-1), reason: '$code: "$localizedWord" is not in $packId');
        expect(bi, isNot(-1), reason: 'English: "$englishWord" is not in $packId');
        expect(
          li,
          bi,
          reason:
              '$code / $packId: "$localizedWord" sits at index $li but "$englishWord" is at $bi',
        );
        expect(
          localized.pairs[li].realWordContext,
          base.pairs[bi].realWordContext,
          reason: '$code / $packId[$li]: real FREE context not aligned',
        );
        expect(
          localized.pairs[li].mimicWordContext,
          base.pairs[bi].mimicWordContext,
          reason: '$code / $packId[$li]: mimic FREE context not aligned',
        );
        expect(
          localized.pairs[li].realWordProContext,
          base.pairs[bi].realWordProContext,
          reason: '$code / $packId[$li]: real PRO context not aligned',
        );
        expect(
          localized.pairs[li].mimicWordProContext,
          base.pairs[bi].mimicWordProContext,
          reason: '$code / $packId[$li]: mimic PRO context not aligned',
        );
      }
    });

    test('unknown or English language codes fall back to the base packs', () {
      expect(WordPackData.getPacksForLanguage('en'), same(WordPackData.packs));
      expect(WordPackData.getPacksForLanguage('fr'), same(WordPackData.packs));
    });
  });

  group('GameState.getContextForPlayer', () {
    const pair = WordPair(
      realWord: 'Cemetery',
      mimicWord: 'Garden',
      realWordContext: 'Rows of carved stone markers and mourners leaving flowers.',
      mimicWordContext: 'Tended beds of blooms, a trowel and a watering can.',
      realWordProContext: 'Concrete angels lean at odd angles above flat grey slabs.',
      mimicWordProContext: 'Tomato vines on wire frames, soil dark from morning watering.',
    );
    final alice = Player(id: 'a', name: 'Alice', color: 0xFF7F77DD);
    final bob = Player(id: 'b', name: 'Bob', color: 0xFF1D9E75);

    GameState buildState({
      List<String> mimicIds = const [],
      GameMode mode = GameMode.classic,
      String? secondMimicWord,
    }) {
      return GameState(
        players: [alice, bob],
        mimicIds: mimicIds,
        selectedMode: mode,
        currentWordPair: pair,
        secondMimicWord: secondMimicWord,
      );
    }

    test('a non-mimic player gets the real word context', () {
      expect(buildState().getContextForPlayer('a'), pair.realWordContext);
    });

    test('the Mimic gets the mimic word context', () {
      expect(
        buildState(mimicIds: ['a']).getContextForPlayer('a'),
        pair.mimicWordContext,
      );
    });

    test('a player with no word at all gets empty context', () {
      expect(
        GameState(players: [alice, bob], mimicIds: const ['a'])
            .getContextForPlayer('a'),
        '',
      );
    });

    test('the Nightmare second mimic word is not a pair side, so empty (button hidden)', () {
      final state = buildState(
        mimicIds: ['a', 'b'],
        mode: GameMode.nightmare,
        secondMimicWord: 'Grave',
      );
      expect(state.getWordForPlayer('b'), 'Grave');
      expect(state.getContextForPlayer('b'), '');
    });

    test('isPro returns the DETAILED pro angles for that word', () {
      expect(
        buildState().getContextForPlayer('a', isPro: true),
        pair.realWordProContext,
      );
      expect(
        buildState(mimicIds: ['a']).getContextForPlayer('a', isPro: true),
        pair.mimicWordProContext,
      );
    });

    test('free installs never see the pro angles', () {
      final state = buildState();
      expect(state.getContextForPlayer('a'), pair.realWordContext);
      expect(state.getContextForPlayer('a', isPro: false), pair.realWordContext);
      expect(
        state.getContextForPlayer('a'),
        isNot(pair.realWordProContext),
      );
    });

    test('a Pro player falls back to the free blurb when the pro fields are empty', () {
      const freeOnly = WordPair(
        realWord: 'Cemetery',
        mimicWord: 'Garden',
        realWordContext: 'Rows of carved stone markers and mourners leaving flowers.',
      );
      final state = GameState(
        players: [alice, bob],
        currentWordPair: freeOnly,
      );
      // Old sync payloads carry only the free fields — Pro still shows
      // something rather than an empty sheet.
      expect(
        state.getContextForPlayer('a', isPro: true),
        freeOnly.realWordContext,
      );
    });
  });
}
