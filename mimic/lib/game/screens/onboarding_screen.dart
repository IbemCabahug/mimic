import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/services/stealth_mode_service.dart';
import 'package:mimic/vault/services/onboarding_service.dart';

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;
  final Color accentColor;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.accentColor,
  });
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    icon: Icons.theaters_rounded,
    title: 'Welcome to Mimic',
    body: 'On the surface, Mimic is a social deduction party game.\nFind the impostor before they find you.\n\nBut there is another layer.',
    accentColor: Color(0xFFC41E3A),
  ),
  _OnboardingPage(
    icon: Icons.lock_outline_rounded,
    title: 'The Hidden Vault',
    body: 'Behind the game lives an AES-256 encrypted vault.\n\nStore photos, videos, audio, notes, and documents — fully local, no cloud, no server. Only you have the key.',
    accentColor: Color(0xFF8B0000),
  ),
  _OnboardingPage(
    icon: Icons.touch_app_rounded,
    title: 'How to Access It',
    body: 'Three secret trigger patterns unlock the vault:\n\n🃏  Voting Screen — Tap card 2 → card 0 → card 2 within 3 seconds\n\n🏆  Results Screen — Tap the top score 3 times within 2 seconds\n\n📖  Tutorial Screen — Secret tap on step 3\n\nThese patterns leave no trace.',
    accentColor: Color(0xFFC41E3A),
  ),
  _OnboardingPage(
    icon: Icons.shield_outlined,
    title: 'Vault Features',
    body: '🔐  PIN + biometric unlock\n🌱  BIP39 recovery phrase\n📸  Intruder selfie capture\n🫨  Shake-to-wipe PIN\n👤  Fake PIN admin panel\n💾  Encrypted .mimic backup files\n🚨  Panic mode auto-lock',
    accentColor: Color(0xFF8B0000),
  ),
  _OnboardingPage(
    icon: Icons.visibility_off_rounded,
    title: 'Stealth Mode',
    body: 'Enable Stealth Mode to make Mimic look like a pure game — no vault hints anywhere in the UI.\n\nThe secret trigger patterns still work silently.\n\nYou can toggle this anytime in vault settings.',
    accentColor: Color(0xFFC41E3A),
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final service = ref.read(onboardingServiceProvider);
    await service.markOnboardingComplete();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool stealth = ref.watch(stealthModeProvider);
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  final isLast = i == _pages.length - 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          page.icon,
                          size: 72,
                          color: page.accentColor,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.creepster(
                            fontSize: 32,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: Colors.white70,
                            height: 1.6,
                          ),
                        ),
                        if (isLast) ...[
                          const SizedBox(height: 32),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFC41E3A).withValues(alpha: 0.4),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.visibility_off_rounded,
                                  color: Color(0xFFC41E3A),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Enable Stealth Mode now',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Hides all vault hints from the UI',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: stealth,
                                  activeThumbColor: const Color(0xFFC41E3A),
                                  onChanged: (v) =>
                                      ref.read(stealthModeProvider.notifier).setStealthMode(v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFC41E3A) : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: _currentPage == _pages.length - 1
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _finish,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC41E3A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'GET STARTED',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _finish,
                          child: Text(
                            'Skip',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC41E3A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'NEXT',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
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
