// lib/game/screens/tutorial_screen.dart
//
// Solo tutorial mode — a 5-step fake how-to-play walkthrough.
// Step 3 secretly embeds the TriggerDetector vault trigger.
// If triggered → glitch transition → PIN screen.
// If completed normally → "You're ready to play!" screen.
//
// This provides the best solo disguise — "Just showing someone how to play"
// is a perfect cover for opening the app alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/core/services/stealth_mode_service.dart';
import 'package:mimic/vault/trigger/trigger_detector.dart';
import 'package:mimic/game/game.dart';

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _progressController;

  static const int _totalSteps = 5;

  // Tutorial step data
  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      title: 'THE GATHERING',
      subtitle: 'Step 1 of 5',
      icon: Icons.people,
      description:
          'Gather 3-8 players around a single device. Each player enters '
          'their name and picks a color. The more players, the more chaos.',
      tip: 'Pro tip: 5-6 players is the sweet spot for maximum suspicion.',
    ),
    _TutorialStep(
      title: 'THE ASSIGNMENT',
      subtitle: 'Step 2 of 5',
      icon: Icons.assignment,
      description:
          'Each player receives a secret word. One player — the MIMIC — gets '
          'a different, related word. Pass the device around privately. '
          'Do NOT reveal your word!',
      tip: 'The Mimic must listen closely to blend in with everyone else.',
    ),
    _TutorialStep(
      title: 'THE DISCUSSION',
      subtitle: 'Step 3 of 5',
      icon: Icons.forum,
      description:
          'Players take turns describing their word without saying it directly. '
          'The Mimic must fake it convincingly. Watch for hesitation, '
          'vague answers, or suspiciously specific descriptions.',
      tip: 'Tap the cards to adjust suspicion levels during discussion.',
      // ↑ Step 3 — the TriggerDetector is secretly embedded here
    ),
    _TutorialStep(
      title: 'THE ACCUSATION',
      subtitle: 'Step 4 of 5',
      icon: Icons.how_to_vote,
      description:
          'After discussion, everyone votes on who they think is the Mimic. '
          'Tap a player card to cast your vote. If the Mimic gets the most '
          'votes, the innocents win!',
      tip: 'Beware — if the Mimic survives the vote, they win the round.',
    ),
    _TutorialStep(
      title: 'THE REVELATION',
      subtitle: 'Step 5 of 5',
      icon: Icons.emoji_events,
      description:
          'The truth is revealed. See who the Mimic was, check the score, '
          'and play another round! Each round, a new Mimic is chosen at random.',
      tip: 'Try Nightmare mode for 2 Mimics with different fake words!',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progressController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _totalSteps) return;
    _fadeController.reverse().then((_) {
      setState(() => _currentStep = step);
      _progressController.forward(from: 0.0);
      _fadeController.forward();
    });
  }

  void _onComplete() {
    // Show "You're ready!" screen, then navigate back
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CompletionDialog(
        onDismiss: () {
          Navigator.of(context).pop(); // close dialog
          Navigator.of(context).pop(); // go back to home
        },
      ),
    );
  }

  /// The secret vault trigger — only available on step 3.
  void _onVaultTriggered() {
    // Navigate to the PIN screen with glitch transition
    Navigator.of(context).push(
      GlitchTransition.pageRoute(
        const _VaultBridge(),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool stealth = ref.watch(stealthModeProvider);
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: SafeArea(
          child: Column(
            children: [
              // ── Top Bar ──
              _buildTopBar(),
              const SizedBox(height: 8),

              // ── Progress Indicator ──
              _buildProgressBar(),
              const SizedBox(height: 24),

              // ── Step Content ──
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildStepContent(step, stealth),
                ),
              ),

              // ── Navigation Buttons ──
              _buildNavButtons(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.fogWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'HOW TO PLAY',
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 22,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(width: 48), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isActive = index <= _currentStep;
          final isCurrent = index == _currentStep;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: isCurrent ? 5 : 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isActive
                      ? HorrorColors.crimson
                      : HorrorColors.cardSurface,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: HorrorColors.crimson.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(_TutorialStep step, bool stealth) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          const SizedBox(height: 32),

          // Step subtitle
          Text(
            step.subtitle,
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray,
              fontSize: 12,
              letterSpacing: 3.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Step title with heartbeat pulse
          HeartbeatPulse(
            child: Text(
              step.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 36,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    blurRadius: 15,
                    color: HorrorColors.bloodRed.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Icon with glow
          _buildStepIcon(step),
          const SizedBox(height: 32),

          // Description text
          // Step 3 layers the TriggerDetector over the content
          _currentStep == 2
              ? Stack(
                  children: [
                    _buildDescriptionCard(step),
                    Positioned.fill(
                      child: TriggerDetector(
                        tapSequence: const [2, 0, 2],
                        onTrigger: _onVaultTriggered,
                      ),
                    ),
                  ],
                )
              : _buildDescriptionCard(step),

          const SizedBox(height: 20),

          // Pro tip — stealth mode swaps step 3's tip text only
          _buildTipCard(
            _currentStep == 2 && stealth
                ? "Tap a player's card to learn more about their role."
                : step.tip,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStepIcon(_TutorialStep step) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HorrorColors.cardSurface,
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: HorrorColors.bloodRed.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(
        step.icon,
        size: 36,
        color: HorrorColors.crimson,
      ),
    );
  }

  Widget _buildDescriptionCard(_TutorialStep step) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HorrorColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Text(
        step.description,
        style: GoogleFonts.inter(
          color: HorrorColors.fogWhite,
          fontSize: 16,
          height: 1.6,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildTipCard(String tip) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HorrorColors.bloodRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: HorrorColors.bloodRed.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: HorrorColors.crimson,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: GoogleFonts.inter(
                color: HorrorColors.fogWhite.withValues(alpha: 0.8),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isFirst = _currentStep == 0;
    final isLast = _currentStep == _totalSteps - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          // Back button
          if (!isFirst)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(_currentStep - 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HorrorColors.ashGray,
                  side: const BorderSide(color: HorrorColors.ashGray),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'BACK',
                  style: GoogleFonts.creepster(
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          if (!isFirst) const SizedBox(width: 16),

          // Next / Finish button
          Expanded(
            flex: isFirst ? 1 : 1,
            child: ElevatedButton(
              onPressed: isLast
                  ? _onComplete
                  : () => _goToStep(_currentStep + 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: HorrorColors.crimson,
                foregroundColor: HorrorColors.fogWhite,
                elevation: 6,
                shadowColor: HorrorColors.crimson.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: HorrorColors.bloodRed, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isLast ? 'DONE' : 'NEXT',
                style: GoogleFonts.creepster(
                  fontSize: 18,
                  letterSpacing: 2.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tutorial Step Data
// ═══════════════════════════════════════════════════════════════════════════

class _TutorialStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final String description;
  final String tip;

  const _TutorialStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.description,
    required this.tip,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Completion Dialog
// ═══════════════════════════════════════════════════════════════════════════

class _CompletionDialog extends StatelessWidget {
  final VoidCallback onDismiss;

  const _CompletionDialog({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: HorrorColors.deepSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: HorrorColors.crimson.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HeartbeatPulse(
              child: Text(
                '🎭',
                style: GoogleFonts.inter(fontSize: 64),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "YOU'RE READY",
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 28,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Now gather your friends and find the Mimic.\n'
              'Trust no one.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HorrorColors.crimson,
                  foregroundColor: HorrorColors.fogWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'BEGIN THE HUNT',
                  style: GoogleFonts.creepster(
                    fontSize: 18,
                    letterSpacing: 2.0,
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

// ═══════════════════════════════════════════════════════════════════════════
// Vault Bridge (navigates to PIN screen)
// ═══════════════════════════════════════════════════════════════════════════

/// Bridge widget that forwards to the vault PIN screen after the
/// glitch transition completes. This keeps the vault import isolated.
class _VaultBridge extends StatelessWidget {
  const _VaultBridge();

  @override
  Widget build(BuildContext context) {
    // Schedule navigation after this frame to avoid build-during-build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(MimicGame.vaultPinRoute);
    });

    // Show a brief black screen during the transition
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.shrink(),
    );
  }
}
