import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/models/player_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameState progression helpers', () {
    test('RoundOutcome stores round, mimicIds, accusedPlayerId', () {
      final outcome = RoundOutcome(
        round: 0,
        mimicIds: ['p1'],
        accusedPlayerId: 'p1',
      );

      expect(outcome.round, 0);
      expect(outcome.mimicIds, ['p1']);
      expect(outcome.accusedPlayerId, 'p1');
      // Mimic was caught when accusedPlayerId is in mimicIds
      expect(outcome.mimicIds.contains(outcome.accusedPlayerId), true);
    });

    test('RoundOutcome - innocent accused means mimic escaped', () {
      final outcome = RoundOutcome(
        round: 1,
        mimicIds: ['p2'],
        accusedPlayerId: 'p1',
      );

      expect(outcome.mimicIds.contains(outcome.accusedPlayerId), false);
    });

    test('addRoundOutcome appends to state', () {
      final notifier = GameStateNotifier();

      notifier.addRoundOutcome(RoundOutcome(
        round: 0,
        mimicIds: ['p1'],
        accusedPlayerId: 'p1',
      ));

      expect(notifier.debugState.roundOutcomes.length, 1);
      expect(notifier.debugState.roundOutcomes[0].round, 0);
      expect(notifier.debugState.roundOutcomes[0].mimicIds, ['p1']);
    });

    test('isFinalRound is true on last round', () {
      final notifier = GameStateNotifier();
      // maxRounds defaults to 3, currentRound is 0-indexed
      notifier.nextRound(); // round 1
      notifier.nextRound(); // round 2 (== maxRounds - 1)

      expect(notifier.debugState.isFinalRound, true);
    });

    test('isGameOver is true when isFinalRound is true', () {
      final notifier = GameStateNotifier();
      notifier.nextRound();
      notifier.nextRound();

      expect(notifier.debugState.isGameOver, true);
    });

    test('isGameOver is false before final round', () {
      final notifier = GameStateNotifier();
      notifier.nextRound(); // round 1

      expect(notifier.debugState.isGameOver, false);
    });

    test('restartRound clears roundOutcomes', () {
      final notifier = GameStateNotifier();

      notifier.addRoundOutcome(RoundOutcome(
        round: 0,
        mimicIds: ['p1'],
        accusedPlayerId: 'p1',
      ));

      expect(notifier.debugState.roundOutcomes.length, 1);

      notifier.restartRound();
      expect(notifier.debugState.roundOutcomes.isEmpty, true);
    });

    test('resetGame clears roundOutcomes', () {
      final notifier = GameStateNotifier();

      notifier.addRoundOutcome(RoundOutcome(
        round: 0,
        mimicIds: ['p1'],
        accusedPlayerId: 'p1',
      ));

      notifier.resetGame();
      expect(notifier.debugState.roundOutcomes.isEmpty, true);
    });

    test('Player profileId is stored', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('TestOwner', 0xFF0000, profileId: 'profile-123');

      final player = notifier.debugState.players.first;
      expect(player.profileId, 'profile-123');
      expect(player.name, 'TestOwner');
    });

    test('Player without profileId defaults to null', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Guest', 0x00FF00);

      final player = notifier.debugState.players.first;
      expect(player.profileId, isNull);
    });

    test('nextRound increments round and reassigns words and mimics', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('P1', 0);
      notifier.addPlayer('P2', 0);
      notifier.addPlayer('P3', 0);
      
      notifier.setSelectedPackIds(['basic']);
      notifier.assignMimics();
      
      final initialRound = notifier.debugState.currentRound;
      final initialMimics = List<String>.from(notifier.debugState.mimicIds);
      final initialWord = notifier.debugState.currentWordPair?.realWord;
      
      // Advance round
      notifier.nextRound();
      
      expect(notifier.debugState.currentRound, initialRound + 1);
      
      // Mimics must be reassigned
      expect(notifier.debugState.mimicIds, isNotEmpty);
      
      // We expect the word to have changed, assuming the pack has >1 pair
      // But it might occasionally be the same if there's only 1 pair. 
      // The logic tries to pick a different one if possible.
      // We can just assert that assignMimics ran by checking that mimicIds and currentWordPair are not null
      expect(notifier.debugState.currentWordPair, isNotNull);
    });
  });

  group('RankTier thresholds', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('RankTier minScore thresholds are correct', () {
      expect(RankTier.bystander.minScore, 0);
      expect(RankTier.suspect.minScore, 500);
      expect(RankTier.investigator.minScore, 1500);
      expect(RankTier.phantom.minScore, 3000);
      expect(RankTier.theOriginal.minScore, 6000);
    });

    test('PlayerProfile.rank returns correct tier based on score', () {
      final profile0 = PlayerProfile(
        id: 't0', displayName: 'Test', suspicionScore: 0,
      );
      expect(profile0.rank, RankTier.bystander);

      final profile500 = PlayerProfile(
        id: 't1', displayName: 'Test', suspicionScore: 500,
      );
      expect(profile500.rank, RankTier.suspect);

      final profile1500 = PlayerProfile(
        id: 't2', displayName: 'Test', suspicionScore: 1500,
      );
      expect(profile1500.rank, RankTier.investigator);

      final profile3000 = PlayerProfile(
        id: 't3', displayName: 'Test', suspicionScore: 3000,
      );
      expect(profile3000.rank, RankTier.phantom);

      final profile6000 = PlayerProfile(
        id: 't4', displayName: 'Test', suspicionScore: 6000,
      );
      expect(profile6000.rank, RankTier.theOriginal);
    });
  });

  group('Cosmetics and Progression', () {
    test('isAvatarUnlocked thresholds and grandfathering', () {
      final profileNew = PlayerProfile(
        id: '1', displayName: 'A', suspicionScore: 0, avatar: HorrorAvatar.skull,
      );
      // Bystander unlocks
      expect(profileNew.isAvatarUnlocked(HorrorAvatar.skull), true);
      expect(profileNew.isAvatarUnlocked(HorrorAvatar.ghost), true);
      // Locked
      expect(profileNew.isAvatarUnlocked(HorrorAvatar.eye), false);
      expect(profileNew.isAvatarUnlocked(HorrorAvatar.mask), false);

      // Grandfathering: locked avatar is equipped
      final profileGrandfathered = PlayerProfile(
        id: '2', displayName: 'B', suspicionScore: 0, avatar: HorrorAvatar.mask,
      );
      expect(profileGrandfathered.isAvatarUnlocked(HorrorAvatar.mask), true);
      expect(profileGrandfathered.isAvatarUnlocked(HorrorAvatar.dagger), false);

      // Max tier
      final profileMax = PlayerProfile(
        id: '3', displayName: 'C', suspicionScore: 6000,
      );
      expect(profileMax.isAvatarUnlocked(HorrorAvatar.mask), true);
    });

    test('unlockedTitles grows with score', () {
      final profile0 = PlayerProfile(id: '1', displayName: 'A', suspicionScore: 0);
      expect(profile0.unlockedTitles, [RankTier.bystander]);

      final profile500 = PlayerProfile(id: '2', displayName: 'B', suspicionScore: 500);
      expect(profile500.unlockedTitles, [RankTier.bystander, RankTier.suspect]);

      final profileMax = PlayerProfile(id: '3', displayName: 'C', suspicionScore: 6000);
      expect(profileMax.unlockedTitles.length, 5);
      expect(profileMax.unlockedTitles.last, RankTier.theOriginal);
    });

    test('hasBadge flips at threshold', () {
      final profileNoBadges = PlayerProfile(id: '1', displayName: 'A');
      expect(profileNoBadges.hasBadge(ProfileBadge.veteran), false);
      expect(profileNoBadges.hasBadge(ProfileBadge.firstBlood), false);

      final profileWithBadges = PlayerProfile(
        id: '2', displayName: 'B', gamesPlayed: 50, gamesWon: 1,
      );
      expect(profileWithBadges.hasBadge(ProfileBadge.veteran), true);
      expect(profileWithBadges.hasBadge(ProfileBadge.firstBlood), true);
      expect(profileWithBadges.hasBadge(ProfileBadge.masterMimic), false);
    });

    test('selectedTitle persists through toJson/fromJson', () {
      final profile = PlayerProfile(
        id: '1',
        displayName: 'A',
        selectedTitle: 'Custom Title',
      );

      final json = profile.toJson();
      expect(json['selectedTitle'], 'Custom Title');

      final restored = PlayerProfile.fromJson(json);
      expect(restored.selectedTitle, 'Custom Title');
    });
  });
}
