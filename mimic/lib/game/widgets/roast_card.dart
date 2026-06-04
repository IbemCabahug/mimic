// lib/game/widgets/roast_card.dart
//
// Auto-generated post-round one-liner humor based on round events.
// Displayed in the Case File screen after each round.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class RoastCard extends StatelessWidget {
  final String playerName;
  final bool wasMimic;
  final bool wasEliminated;
  final bool votedCorrectly;

  const RoastCard({
    super.key,
    required this.playerName,
    required this.wasMimic,
    required this.wasEliminated,
    required this.votedCorrectly,
  });

  @override
  Widget build(BuildContext context) {
    final roast = _generateRoast();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HorrorColors.deepSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fire emoji
          const Text('🔥', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playerName,
                  style: GoogleFonts.creepster(
                    color: HorrorColors.crimson,
                    fontSize: 16,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  roast,
                  style: GoogleFonts.inter(
                    color: HorrorColors.fogWhite.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _generateRoast() {
    final random = math.Random(playerName.hashCode);

    if (wasMimic && !wasEliminated) {
      return _pick(random, _mimicWonRoasts);
    } else if (wasMimic && wasEliminated) {
      return _pick(random, _mimicCaughtRoasts);
    } else if (wasEliminated && !wasMimic) {
      return _pick(random, _innocentEliminatedRoasts);
    } else if (votedCorrectly) {
      return _pick(random, _correctVoteRoasts);
    } else {
      return _pick(random, _wrongVoteRoasts);
    }
  }

  String _pick(math.Random random, List<String> options) {
    return options[random.nextInt(options.length)];
  }

  // ─────────────────────────────────────────────────────────────────────
  // Roast Templates
  // ─────────────────────────────────────────────────────────────────────

  static const List<String> _mimicWonRoasts = [
    'Oscar-worthy performance. Everyone fell for it.',
    'Walked into the lion\'s den and walked out wearing the lion.',
    'Professional con artist energy. Scary good.',
    'Made everyone look like amateurs. Respect.',
    'The devil doesn\'t always wear red — sometimes they just smile.',
    'You could sell ice to a penguin. Nobody suspected a thing.',
  ];

  static const List<String> _mimicCaughtRoasts = [
    'That poker face needs some work.',
    'Tried to blend in. Failed spectacularly.',
    'Your acting career ended today.',
    'Pretended to know the word. We all saw through it.',
    'The disguise was about as convincing as a cat in a dog suit.',
    'Got caught red-handed. Literally.',
  ];

  static const List<String> _innocentEliminatedRoasts = [
    'Eliminated by your own team. That\'s gotta sting.',
    'The real crime was the friends who voted against you.',
    'Innocent but suspicious. The worst combination.',
    'Thrown under the bus by democracy. Classic.',
    'You were too good at being vague. That\'s on you.',
    'Sacrificed for the greater good. Or was it?',
  ];

  static const List<String> _correctVoteRoasts = [
    'Saw through the deception. Detective material.',
    'Sharp eyes. The Mimic couldn\'t fool you.',
    'Trusted your gut and it paid off.',
    'One of the few with actual brainpower this round.',
    'Called it from the start. Natural instincts.',
    'Saw the truth when everyone else was blind.',
  ];

  static const List<String> _wrongVoteRoasts = [
    'Voted for the wrong person. Bold strategy.',
    'Confidently incorrect. A Mimic\'s best friend.',
    'Your trust issues need trust issues.',
    'The Mimic thanks you for your service.',
    'You pointed the finger... at an innocent player. Yikes.',
    'Accidentally helped the enemy. It happens to the best of us.',
  ];
}
