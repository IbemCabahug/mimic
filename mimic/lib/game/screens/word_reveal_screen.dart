// lib/game/screens/word_reveal_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/game_state.dart';
import 'package:mimic/game/game.dart';

class WordRevealScreen extends ConsumerStatefulWidget {
  const WordRevealScreen({super.key});

  @override
  ConsumerState<WordRevealScreen> createState() => _WordRevealScreenState();
}

class _WordRevealScreenState extends ConsumerState<WordRevealScreen> {
  int _currentIndex = 0;
  bool _wordRevealed = false;
  Timer? _revealTimer;
  late String _selectedWord;
  late String _mimicWord;
  late String _category;

  // Expanded word pool organized by categories
  static const Map<String, List<Map<String, String>>> _wordCategories = {
    '🌍 Places': [
      {'real': 'Ocean', 'mimic': 'Lake'},
      {'real': 'Mountain', 'mimic': 'Hill'},
      {'real': 'Forest', 'mimic': 'Grove'},
      {'real': 'Desert', 'mimic': 'Savanna'},
      {'real': 'River', 'mimic': 'Stream'},
      {'real': 'Castle', 'mimic': 'Mansion'},
      {'real': 'Beach', 'mimic': 'Shore'},
      {'real': 'Volcano', 'mimic': 'Geyser'},
      {'real': 'Island', 'mimic': 'Peninsula'},
      {'real': 'Cave', 'mimic': 'Tunnel'},
    ],
    '🍕 Food': [
      {'real': 'Pizza', 'mimic': 'Calzone'},
      {'real': 'Sushi', 'mimic': 'Sashimi'},
      {'real': 'Burger', 'mimic': 'Sandwich'},
      {'real': 'Pasta', 'mimic': 'Noodles'},
      {'real': 'Cake', 'mimic': 'Pie'},
      {'real': 'Taco', 'mimic': 'Burrito'},
      {'real': 'Soup', 'mimic': 'Stew'},
      {'real': 'Donut', 'mimic': 'Bagel'},
      {'real': 'Pancake', 'mimic': 'Waffle'},
      {'real': 'Ice Cream', 'mimic': 'Gelato'},
    ],
    '🎭 Actions': [
      {'real': 'Dancing', 'mimic': 'Swaying'},
      {'real': 'Swimming', 'mimic': 'Floating'},
      {'real': 'Running', 'mimic': 'Jogging'},
      {'real': 'Singing', 'mimic': 'Humming'},
      {'real': 'Painting', 'mimic': 'Drawing'},
      {'real': 'Flying', 'mimic': 'Gliding'},
      {'real': 'Climbing', 'mimic': 'Hiking'},
      {'real': 'Cooking', 'mimic': 'Baking'},
      {'real': 'Sleeping', 'mimic': 'Napping'},
      {'real': 'Jumping', 'mimic': 'Hopping'},
    ],
    '🐾 Animals': [
      {'real': 'Lion', 'mimic': 'Tiger'},
      {'real': 'Eagle', 'mimic': 'Hawk'},
      {'real': 'Dolphin', 'mimic': 'Porpoise'},
      {'real': 'Wolf', 'mimic': 'Fox'},
      {'real': 'Bear', 'mimic': 'Panda'},
      {'real': 'Horse', 'mimic': 'Donkey'},
      {'real': 'Shark', 'mimic': 'Whale'},
      {'real': 'Owl', 'mimic': 'Raven'},
      {'real': 'Rabbit', 'mimic': 'Hare'},
      {'real': 'Frog', 'mimic': 'Toad'},
    ],
    '🎬 Movies': [
      {'real': 'Batman', 'mimic': 'Superman'},
      {'real': 'Harry Potter', 'mimic': 'Lord of the Rings'},
      {'real': 'Titanic', 'mimic': 'Poseidon'},
      {'real': 'Star Wars', 'mimic': 'Star Trek'},
      {'real': 'Frozen', 'mimic': 'Tangled'},
      {'real': 'Avengers', 'mimic': 'Justice League'},
      {'real': 'Toy Story', 'mimic': 'Monsters Inc'},
      {'real': 'Matrix', 'mimic': 'Inception'},
      {'real': 'Jaws', 'mimic': 'Piranha'},
      {'real': 'Rocky', 'mimic': 'Rambo'},
    ],
    '🏢 Objects': [
      {'real': 'Guitar', 'mimic': 'Ukulele'},
      {'real': 'Bicycle', 'mimic': 'Scooter'},
      {'real': 'Laptop', 'mimic': 'Tablet'},
      {'real': 'Umbrella', 'mimic': 'Parasol'},
      {'real': 'Mirror', 'mimic': 'Window'},
      {'real': 'Piano', 'mimic': 'Organ'},
      {'real': 'Candle', 'mimic': 'Lantern'},
      {'real': 'Sword', 'mimic': 'Dagger'},
      {'real': 'Crown', 'mimic': 'Tiara'},
      {'real': 'Telescope', 'mimic': 'Binoculars'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _pickRandomWord();
  }

  void _pickRandomWord() {
    final random = Random();
    final categories = _wordCategories.keys.toList();
    _category = categories[random.nextInt(categories.length)];
    final words = _wordCategories[_category]!;
    final wordPair = words[random.nextInt(words.length)];
    _selectedWord = wordPair['real']!;
    _mimicWord = wordPair['mimic']!;

    // Store the word in game state for reference
    ref.read(gameStateProvider.notifier).setCurrentWord(_selectedWord);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _revealWord() {
    setState(() {
      _wordRevealed = true;
    });
    _revealTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _wordRevealed = false;
        });
      }
    });
  }

  void _nextPlayer() {
    _revealTimer?.cancel();
    final gameState = ref.read(gameStateProvider);
    if (_currentIndex < gameState.players.length - 1) {
      setState(() {
        _currentIndex++;
        _wordRevealed = false;
      });
    } else {
      Navigator.of(context).pushNamed(MimicGame.discussionRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState.players.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F14),
        body: Center(child: Text('No players', style: TextStyle(color: Colors.white))),
      );
    }

    final currentPlayer = gameState.players[_currentIndex];
    final isMimic = currentPlayer.id == gameState.mimicId;
    final wordToShow = isMimic ? _mimicWord : _selectedWord;

    final allPlayersViewed = _currentIndex >= gameState.players.length - 1 && !_wordRevealed;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1}/${gameState.players.length}',
          style: const TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7F77DD).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _category,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7F77DD),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Player avatar
            CircleAvatar(
              radius: 36,
              backgroundColor: Color(currentPlayer.color),
              child: Text(
                currentPlayer.name.isNotEmpty
                    ? currentPlayer.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              currentPlayer.name,
              style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pass the phone to this player',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 40),
            if (_wordRevealed)
              AnimatedOpacity(
                opacity: _wordRevealed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    Text(
                      wordToShow,
                      style: const TextStyle(
                        fontSize: 44,
                        color: Color(0xFF7F77DD),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isMimic ? 'You are the Mimic!' : 'Remember your word!',
                      style: TextStyle(
                        fontSize: 14,
                        color: isMimic
                            ? const Color(0xFFD85A30)
                            : const Color(0xFF1D9E75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Tap to reveal your word',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            const SizedBox(height: 40),
            if (!_wordRevealed)
              ElevatedButton(
                onPressed: _revealWord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F77DD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reveal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: _nextPlayer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F77DD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  allPlayersViewed ? 'Start Discussion' : 'Next Player',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({super.key});

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  late Timer _timer;
  int _secondsRemaining = 90;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        Navigator.of(context).pushNamed(MimicGame.votingRoute);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _timeString {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Discussion',
          style: TextStyle(
            color: Color(0xFF7F77DD),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: CircularProgressIndicator(
                          value: _secondsRemaining / 90,
                          strokeWidth: 8,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _secondsRemaining > 30
                                ? const Color(0xFF7F77DD)
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _timeString,
                            style: TextStyle(
                              fontSize: 48,
                              color: _secondsRemaining > 30
                                  ? Colors.white
                                  : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'REMAINING',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.5,
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton.icon(
                    onPressed: () {
                      _timer.cancel();
                      Navigator.of(context).pushNamed(MimicGame.votingRoute);
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'Start Voting Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Inter',
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F77DD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF7F77DD).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Players',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: gameState.players.map((player) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Color(player.color).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Color(player.color).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          player.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
