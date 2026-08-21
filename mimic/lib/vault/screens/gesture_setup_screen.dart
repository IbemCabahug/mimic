// lib/vault/screens/gesture_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/horror_theme.dart';
import '../trigger/gesture_store.dart';

enum _SetupPhase { create, confirm }

/// Standalone vault creation gesture chooser screen.
///
/// Presents three fixed candidate cards resembling the game voting screen,
/// allowing the user to select and confirm an unlock gesture of exactly three taps.
class GestureSetupScreen extends StatefulWidget {
  const GestureSetupScreen({
    super.key,
    this.store,
    this.onComplete,
    this.allowCancel = false,
  });

  final GestureStore? store;
  final VoidCallback? onComplete;
  final bool allowCancel;

  @override
  State<GestureSetupScreen> createState() => _GestureSetupScreenState();
}

class _GestureSetupScreenState extends State<GestureSetupScreen> {
  late final GestureStore _store;
  _SetupPhase _phase = _SetupPhase.create;
  final List<int> _currentTaps = [];
  List<int>? _firstSequence;
  String? _errorMessage;
  bool _isSaving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? GestureStore();
  }

  void _onCardTapped(int index) {
    if (_saved || _currentTaps.length >= 3 || _isSaving) return;

    setState(() {
      _currentTaps.add(index);
      _errorMessage = null;
    });
  }

  void _onStartOver() {
    if (_saved || _isSaving) return;
    setState(() {
      _currentTaps.clear();
      _firstSequence = null;
      _errorMessage = null;
      _phase = _SetupPhase.create;
    });
  }

  Future<void> _onContinue() async {
    if (_saved || _currentTaps.length != 3 || _isSaving) return;

    if (_phase == _SetupPhase.create) {
      if (_currentTaps.every((t) => t == _currentTaps.first)) {
        setState(() {
          _errorMessage = 'All three taps cannot be identical. Choose a different sequence.';
          _currentTaps.clear();
        });
        return;
      }

      setState(() {
        _firstSequence = List<int>.from(_currentTaps);
        _currentTaps.clear();
        _errorMessage = null;
        _phase = _SetupPhase.confirm;
      });
    } else {
      // Confirm phase
      final first = _firstSequence;
      if (first == null ||
          first.length != 3 ||
          first[0] != _currentTaps[0] ||
          first[1] != _currentTaps[1] ||
          first[2] != _currentTaps[2]) {
        setState(() {
          _errorMessage = 'Sequences do not match. Please try again from the beginning.';
          _firstSequence = null;
          _currentTaps.clear();
          _phase = _SetupPhase.create;
        });
        return;
      }

      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      try {
        await _store.setGesture(List<int>.from(_currentTaps));
        if (mounted) {
          setState(() {
            _isSaving = false;
            _saved = true;
          });
          widget.onComplete?.call();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to save gesture sequence. Please try again.';
            _firstSequence = null;
            _currentTaps.clear();
            _phase = _SetupPhase.create;
            _isSaving = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _phase == _SetupPhase.create;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: widget.allowCancel
            ? IconButton(
                key: const ValueKey('gesture_cancel'),
                icon: const Icon(Icons.close, color: HorrorColors.ashGray),
                tooltip: 'Cancel',
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          'STEALTH GESTURE',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 22,
            letterSpacing: 1.5,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              // Heading
              Text(
                isCreate ? 'Choose your sequence' : 'Repeat your sequence',
                key: const ValueKey('gesture_heading'),
                textAlign: TextAlign.center,
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 24,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // Instruction (Create phase only, when not saved)
              if (isCreate && !_saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Choose three taps. In a real game, voting for a player records that player\'s position. Tap the same three positions in the same order, within three seconds, to open your vault. Write this down with your recovery words.',
                    key: const ValueKey('gesture_instruction'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: HorrorColors.ashGray,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),

              // Error display
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    key: const ValueKey('gesture_error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // Saved Confirmation State
              if (_saved)
                Expanded(
                  child: Center(
                    child: Text(
                      'SEQUENCE SAVED',
                      key: const ValueKey('gesture_saved'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.creepster(
                        color: HorrorColors.crimson,
                        fontSize: 28,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ),

              // Progress Dots and Cards (only when not saved)
              if (!_saved) ...[
                // Progress Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    final isFilled = index < _currentTaps.length;
                    return Container(
                      key: ValueKey('gesture_dot_$index'),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled ? HorrorColors.crimson : Colors.transparent,
                        border: Border.all(
                          color: isFilled ? HorrorColors.bloodRed : HorrorColors.ashGray,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                // 3 Candidate Cards arranged in a 2-column grid.
                // These layout parameters (crossAxisCount, spacing, aspect ratio)
                // are deliberately mirrored from voting_screen.dart so practice transfers
                // accurately to the real voting layout. Note: the 20px horizontal inset is
                // supplied by the body Padding rather than by the grid.
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.85,
                    padding: EdgeInsets.zero,
                    children: [
                      _buildCandidateCard(0, 'PLAYER ONE', '1', const ValueKey('gesture_card_0')),
                      _buildCandidateCard(1, 'PLAYER TWO', '2', const ValueKey('gesture_card_1')),
                      _buildCandidateCard(2, 'PLAYER THREE', '3', const ValueKey('gesture_card_2')),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Buttons: Continue and Start Over
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      key: const ValueKey('gesture_continue'),
                      onPressed: (!_saved && _currentTaps.length == 3 && !_isSaving)
                          ? _onContinue
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HorrorColors.crimson,
                        foregroundColor: HorrorColors.fogWhite,
                        disabledBackgroundColor: HorrorColors.cardSurface,
                        disabledForegroundColor: HorrorColors.ashGray,
                        side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _isSaving ? 'SAVING' : 'CONTINUE',
                        style: GoogleFonts.creepster(
                          fontSize: 20,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      key: const ValueKey('gesture_startover'),
                      onPressed: (!_saved && !_isSaving) ? _onStartOver : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HorrorColors.ashGray,
                        side: const BorderSide(color: HorrorColors.ashGray, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'START OVER',
                        style: GoogleFonts.creepster(
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateCard(int index, String title, String digit, Key key) {
    return GestureDetector(
      key: key,
      onTap: () => _onCardTapped(index),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: HorrorColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: HorrorColors.darkRedTint,
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: HorrorColors.bloodRed,
              child: Text(
                digit,
                style: GoogleFonts.creepster(
                  color: HorrorColors.fogWhite,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.creepster(
                color: HorrorColors.fogWhite,
                fontSize: 18,
                letterSpacing: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
