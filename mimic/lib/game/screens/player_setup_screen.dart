// lib/game/screens/player_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/game_state.dart';
import 'package:mimic/game/game.dart';

class PlayerSetupScreen extends ConsumerStatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  ConsumerState<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends ConsumerState<PlayerSetupScreen> {
  final List<PlayerEntry> _players = [];
  final List<int> _playerColors = [
    0xFF7F77DD,
    0xFF1D9E75,
    0xFFD85A30,
    0xFF378ADD,
    0xFFD4537E,
    0xFFEF9F27,
    0xFF5DCAA5,
    0xFFF09595,
  ];

  @override
  void initState() {
    super.initState();
    _addPlayer();
    _addPlayer();
  }

  void _addPlayer() {
    if (_players.length >= 8) return;
    setState(() {
      _players.add(PlayerEntry(color: _playerColors[_players.length]));
    });
  }

  void _removePlayer(int index) {
    setState(() {
      _players.removeAt(index);
    });
  }

  void _startGame() {
    final namedPlayers = _players.where((p) => p.nameController.text.isNotEmpty).toList();
    if (namedPlayers.length < 2) return;

    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    for (int i = 0; i < namedPlayers.length; i++) {
      gameStateNotifier.addPlayer(
        namedPlayers[i].nameController.text,
        namedPlayers[i].color,
      );
    }
    gameStateNotifier.assignMimic();

    Navigator.of(context).pushNamed(MimicGame.wordRevealRoute);
  }

  bool get _canStart => _players.where((p) => p.nameController.text.isNotEmpty).length >= 2;

  @override
  void dispose() {
    for (final player in _players) {
      player.nameController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Player Setup',
          style: TextStyle(color: Color(0xFF7F77DD)),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF7F77DD),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _players.length,
              itemBuilder: (context, index) {
                final player = _players[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(player.color),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: player.nameController,
                          onChanged: (value) => setState(() {}),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Player ${index + 1} name',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0x337F77DD)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0x337F77DD)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF7F77DD)),
                            ),
                          ),
                        ),
                      ),
                      if (_players.length > 2)
                        IconButton(
                          icon: const Icon(Icons.remove, color: Colors.white54),
                          onPressed: () => _removePlayer(index),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_players.length < 8)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addPlayer,
                      icon: const Icon(Icons.add, color: Color(0xFF7F77DD)),
                      label: const Text(
                        'Add Player',
                        style: TextStyle(color: Color(0xFF7F77DD)),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0x337F77DD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canStart ? _startGame : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7F77DD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'Start Game',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerEntry {
  final TextEditingController nameController;
  final int color;

  PlayerEntry({required this.color}) : nameController = TextEditingController();
}