// lib/game/screens/mode_select_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/game.dart';

class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);
    final selectedMode = gameState.gameMode;
    final notifier = ref.read(gameStateProvider.notifier);

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SELECT MODE',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 28,
            letterSpacing: 2.0,
          ),
        ),
        iconTheme: const IconThemeData(color: HorrorColors.crimson),
      ),
      body: StaticOverlay(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                children: [
                  Text(
                    'CHOOSE YOUR NIGHTMARE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.creepster(
                      color: HorrorColors.ashGray,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 1. Classic Mode Card
                  _buildModeCard(
                    context: context,
                    mode: GameMode.classic,
                    title: 'CLASSIC',
                    subtitle: 'Find the one among you.',
                    icon: Icons.visibility_outlined,
                    isSelected: selectedMode == GameMode.classic,
                    onTap: () => notifier.setGameMode(GameMode.classic),
                  ),
                  const SizedBox(height: 16),
                  
                  // 2. Nightmare Mode Card
                  _buildModeCard(
                    context: context,
                    mode: GameMode.nightmare,
                    title: 'NIGHTMARE',
                    subtitle: "There are two. They don't know each other.",
                    icon: Icons.dangerous_outlined,
                    isSelected: selectedMode == GameMode.nightmare,
                    onTap: () => notifier.setGameMode(GameMode.nightmare),
                  ),
                  const SizedBox(height: 16),
                  
                  // 3. Survival Mode Card
                  _buildModeCard(
                    context: context,
                    mode: GameMode.survival,
                    title: 'SURVIVAL',
                    subtitle: 'Only one walks away.',
                    icon: Icons.local_fire_department_outlined,
                    isSelected: selectedMode == GameMode.survival,
                    onTap: () => notifier.setGameMode(GameMode.survival),
                  ),
                ],
              ),
            ),

            // Bottom Proceed Button
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      // Navigate to PlayerSetupScreen
                      Navigator.of(context).pushNamed(MimicGame.playerSetupRoute);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HorrorColors.crimson,
                      foregroundColor: HorrorColors.fogWhite,
                      elevation: 6,
                      shadowColor: HorrorColors.crimson.withValues(alpha: 0.4),
                      side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'PROCEED',
                      style: GoogleFonts.creepster(
                        fontSize: 22,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required GameMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        decoration: BoxDecoration(
          color: HorrorColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? HorrorColors.crimson : HorrorColors.darkRedTint,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: HorrorColors.crimson.withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? HorrorColors.crimson.withValues(alpha: 0.15)
                    : HorrorColors.deepSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? HorrorColors.crimson : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: isSelected ? HorrorColors.crimson : HorrorColors.ashGray,
                size: 32,
              ),
            ),
            const SizedBox(width: 20),
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.creepster(
                      fontSize: 24,
                      color: isSelected ? HorrorColors.crimson : HorrorColors.fogWhite,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: HorrorColors.ashGray,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
