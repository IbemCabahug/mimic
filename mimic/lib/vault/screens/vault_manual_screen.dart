// lib/vault/screens/vault_manual_screen.dart
//
// F30 — the vault field manual: an always-available guide to how the vault
// behaves (locking, auto-lock, unlock methods, quick entry, recovery,
// backups, staying hidden). Opened automatically on the first visit after
// the first successful unlock, and reachable forever from the vault home
// app bar and Settings > Guide.
//
// Deliberately styled with the calm vault theme (VaultColors / vaultTheme),
// never the horror theme: this screen lives inside the vault, where the
// game is the decoy and everything looks like an ordinary utility app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/onboarding_service.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class VaultManualScreen extends ConsumerStatefulWidget {
  const VaultManualScreen({super.key});

  @override
  ConsumerState<VaultManualScreen> createState() => _VaultManualScreenState();
}

class _VaultManualScreenState extends ConsumerState<VaultManualScreen> {
  /// True when the screen was opened because the manual has never been
  /// acknowledged — the first-run walkthrough shows the GOT IT button.
  bool _firstRun = false;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _decideFirstRun();
  }

  Future<void> _decideFirstRun() async {
    try {
      final seen =
          await ref.read(onboardingServiceProvider).isVaultManualSeen();
      if (mounted) {
        setState(() {
          _firstRun = !seen;
          _decided = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _firstRun = false;
          _decided = true;
        });
      }
    }
  }

  Future<void> _acknowledge() async {
    try {
      await ref.read(onboardingServiceProvider).markVaultManualSeen();
    } catch (_) {
      // Acknowledging must never block leaving the screen.
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Fire-and-forget acknowledgement used by the PopScope exit paths. No
  /// await, no setState: the screen is already leaving. Swallows storage
  /// errors so an exit can never be blocked by a write.
  void _markSeenQuietly() {
    unawaited(
      ref.read(onboardingServiceProvider).markVaultManualSeen().catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFirstRun = _decided && _firstRun;
    // The manual records itself as seen on EVERY exit (GOT IT, app-bar back,
    // system back, swipe). Writing unconditionally is deliberate: it closes
    // the race where the owner leaves before the first-run read resolves, and
    // the flag only ever answers "has this ever been shown", so an extra
    // idempotent write costs nothing.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _markSeenQuietly();
        }
      },
      child: VaultScaffold(
        title: 'Field Manual',
        showLockButton: false,
        body: Column(
          children: [
            if (showFirstRun) const _FirstRunBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  const _ManualSection(
                    icon: Icons.help_outline,
                    title: 'WHAT THIS PLACE IS',
                    lines: [
                      'An encrypted space for your photos, notes, videos and '
                          'documents. Everything here is encrypted at rest and only '
                          'readable after unlock.',
                      'To anyone holding your phone, this is just a horror party '
                          'game. Nothing in the game points here.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.vpn_key_outlined,
                    title: 'GETTING BACK IN',
                    lines: [
                      'The way in is the secret tap sequence you chose, entered during '
                          'a real round: on the voting screen, tap the players in your '
                          'order. Three taps open the PIN screen. If you have not '
                          'chosen a sequence yet, set one in Settings > Unlock Gesture.',
                      'The PIN is the real key. The tap sequence only opens the door.',
                      'Biometric Unlock can be Off, a shortcut straight to the PIN '
                          'screen (Vault), or set to open the admin panel (decoy). '
                          'Change it in Settings > Biometric Unlock.',
                      'Recovery Phrase is the 12-word backup for the day the PIN is '
                          'gone. Keep it off this phone.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.visibility_off_outlined,
                    title: 'STAYING HIDDEN',
                    lines: [
                      'The app switcher never shows these screens, and the back '
                          'button returns you to the game.',
                      'If you enabled shake-to-hide, a sharp shake locks the vault '
                          'and drops you straight back into the game.',
                      'Stealth Mode takes every vault hint out of the game. The '
                          'secret tap sequence still works.',
                      'Hide App Icon removes Mimic from the app drawer. Reopen it '
                          'through Android Settings > Apps > Mimic > Open.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.lock_outline,
                    title: 'LOCKING',
                    lines: [
                      'Lock anytime from Settings > Lock Vault, or with the lock '
                          'button on the home screen.',
                      'Auto-lock: choose in Settings how long the vault waits '
                          'before locking itself after inactivity. Locking wipes '
                          'the key from memory — the files stay encrypted, and '
                          'leaving the app locks it too.',
                      'The shorter idle windows are free; the longer ones are Pro. '
                          'Whatever you pick, the platform backstop closes the vault '
                          'eventually, so it never stays open forever.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.touch_app_outlined,
                    title: 'QUICK ENTRY (PRO)',
                    lines: [
                      'Off by default. Turn on Settings > Quick entry to skip the tap '
                          'sequence: from then on, a long-press on the MIMIC title on '
                          'the game home screen goes straight to the PIN screen.',
                      'The PIN is still required. Nothing is skipped except the '
                          'sequence itself, so a stranger who long-presses the logo '
                          'sees nothing at all unless the PIN follows.',
                      'Turn it off any time; the long-press goes back to being an '
                          'ordinary, dead press on the title.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.theater_comedy_outlined,
                    title: 'DECOYS AND LOGS',
                    lines: [
                      'Duress PIN is a second PIN that opens a harmless admin panel '
                          'instead of your files. Set it in Settings > Duress PIN. Use '
                          'it if someone is forcing you to unlock.',
                      'Intruder Logs record failed PIN attempts and capture a photo of '
                          'whoever is trying. Read them in Settings > Intruder Logs.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.backup_outlined,
                    title: 'BACKUPS',
                    lines: [
                      'Export Vault writes a .mimic file that is still encrypted. '
                          'Import Vault restores it on a new phone.',
                      'A backup that lives only on this phone is not a backup. Keep a '
                          'copy on storage you control, offline if you can.',
                      'Nothing here is ever stored unencrypted. If the PIN and the '
                          'recovery phrase are both gone, the files cannot be read by '
                          'anyone, including us.',
                    ],
                  ),
                  const _ManualSection(
                    icon: Icons.build_outlined,
                    title: 'IF SOMETHING IS WRONG',
                    lines: [
                      'Files missing after a restore? Import the newest .mimic backup '
                          'in Settings > Import Vault, then check the counts on the '
                          'home screen.',
                      'Vault opens but looks empty? You may be in the decoy admin '
                          'panel from the duress PIN. Lock, then unlock with your real '
                          'PIN.',
                      'Forgot the PIN? Enter your 12-word Recovery Phrase when asked, '
                          'then set a new PIN.',
                      'App icon gone? Android Settings > Apps > Mimic > Open. This is '
                          'expected while Hide App Icon is on.',
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 24),
                    child: Text(
                      'The rule that matters: never hand the phone over while '
                      'this vault is open, and never show anyone the way in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: VaultColors.textTertiary,
                        fontFamily: 'Inter',
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showFirstRun) _GotItBar(onPressed: _acknowledge),
          ],
        ),
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;

  const _ManualSection({
    required this.icon,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: VaultColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: VaultColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: VaultColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final line in lines) ...[
              Text(
                line,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VaultColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one-time strip shown above the walkthrough on the very first visit.
/// It exists so the owner knows the manual is permanent before reading it,
/// and does not try to memorise the whole screen in one sitting.
class _FirstRunBanner extends StatelessWidget {
  const _FirstRunBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VaultColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VaultColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.waving_hand_outlined,
            size: 20,
            color: VaultColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'First time in here. Read it once and you are set. This manual '
              'stays available from the ? button on the home screen and from '
              'Settings > Field Manual.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VaultColors.textPrimary,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first-run dismissal bar. GOT IT is the explicit acknowledgement; the
/// surrounding PopScope covers the back button, system back and swipe exits.
class _GotItBar extends StatelessWidget {
  final VoidCallback onPressed;

  const _GotItBar({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: const BoxDecoration(
        color: VaultColors.background,
        border: Border(top: BorderSide(color: Color(0xFFE8E5DC))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Reopen it any time from the ? button or Settings > Field Manual. '
            'It will not open on its own again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VaultColors.textSecondary,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: VaultColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'GOT IT',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

