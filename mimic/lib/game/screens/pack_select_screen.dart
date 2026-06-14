// lib/game/screens/pack_select_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/game.dart';

class PackSelectScreen extends ConsumerStatefulWidget {
  const PackSelectScreen({super.key});

  @override
  ConsumerState<PackSelectScreen> createState() => _PackSelectScreenState();
}

class _PackSelectScreenState extends ConsumerState<PackSelectScreen> {
  final List<String> _selectedPackIds = [];

  @override
  void initState() {
    super.initState();
    // Default select the first pack ("Dark Places")
    _selectedPackIds.add(WordPackData.packs.first.id);
  }

  void _togglePack(String id) {
    setState(() {
      if (_selectedPackIds.contains(id)) {
        // Must keep at least one pack selected
        if (_selectedPackIds.length > 1) {
          _selectedPackIds.remove(id);
        }
      } else {
        // Enforce maximum of 3 mixed packs
        if (_selectedPackIds.length < 3) {
          _selectedPackIds.add(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: HorrorColors.deepSurface,
              content: Text(
                'MAXIMUM 3 PACKS CAN BE MIXED.',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  void _confirmSelection() {
    if (_selectedPackIds.isEmpty || _selectedPackIds.length > 3) return;

    final notifier = ref.read(gameStateProvider.notifier);
    // Save selected packs in Riverpod GameState
    notifier.setSelectedPackIds(_selectedPackIds);
    // Select the words and mimics from the chosen packs
    notifier.assignMimics();

    // Proceed to the Word Reveal screen
    Navigator.of(context).pushNamed(MimicGame.wordRevealRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'WORD CATEGORIES',
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
            // Instructions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Text(
                'MIX 1 TO 3 THEME PACKS FOR THIS ROUND',
                textAlign: TextAlign.center,
                style: GoogleFonts.creepster(
                  color: HorrorColors.ashGray,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
            ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                itemCount: WordPackData.packs.length,
                itemBuilder: (context, index) {
                  final pack = WordPackData.packs[index];
                  final isSelected = _selectedPackIds.contains(pack.id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14.0),
                    child: GestureDetector(
                      onTap: () => _togglePack(pack.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16.0),
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
                                    color: HorrorColors.crimson.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon + Selection Marker
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? HorrorColors.crimson.withValues(alpha: 0.1)
                                        : HorrorColors.deepSurface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    pack.icon,
                                    color: isSelected ? HorrorColors.crimson : HorrorColors.ashGray,
                                    size: 28,
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: HorrorColors.crimson,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        color: HorrorColors.fogWhite,
                                        size: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        pack.name.toUpperCase(),
                                        style: GoogleFonts.creepster(
                                          fontSize: 20,
                                          color: isSelected ? HorrorColors.crimson : HorrorColors.fogWhite,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      // Word count badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: HorrorColors.crimson.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: HorrorColors.crimson, width: 0.8),
                                        ),
                                        child: Text(
                                          '${pack.pairs.length} PAIRS',
                                          style: GoogleFonts.inter(
                                            color: HorrorColors.fogWhite,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    pack.description,
                                    style: GoogleFonts.inter(
                                      color: HorrorColors.ashGray,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Confirm Button
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selectedPackIds.isNotEmpty ? _confirmSelection : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HorrorColors.crimson,
                      foregroundColor: HorrorColors.fogWhite,
                      disabledBackgroundColor: HorrorColors.cardSurface,
                      disabledForegroundColor: HorrorColors.ashGray,
                      side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'CONFIRM PACKS',
                      style: GoogleFonts.creepster(
                        fontSize: 20,
                        letterSpacing: 1.5,
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
}
