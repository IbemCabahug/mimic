import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late Timer _taglineTimer;
  int _taglineIndex = 0;

  final List<String> _taglines = [
    'Trust no one.',
    'One of you is lying.',
    'Who is the mimic?',
    'Blend in. Survive.',
    'Someone is not who they seem.',
  ];

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _taglineTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (mounted) {
        setState(() {
          _taglineIndex = (_taglineIndex + 1) % _taglines.length;
        });
      }
    });

    _startBootSequence();
  }

  Future<void> _startBootSequence() async {
    // Await the required 2-second display delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      // Navigate to the main home screen
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _taglineTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with Glow and Fade-in
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Breathing Glow
                    AnimatedBuilder(
                      animation: _glowAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _glowAnimation.value,
                          child: Opacity(
                            opacity: _glowAnimation.value * 0.4,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: HorrorColors.crimson,
                                    blurRadius: 40,
                                    spreadRadius: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Logo Image with one-time 600ms fade-in
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeIn,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        width: 140,
                        height: 140,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'MIMIC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8.0,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Rotating Tagline
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _taglines[_taglineIndex],
                    key: ValueKey<int>(_taglineIndex),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Progress Indicator at bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: HorrorColors.crimson.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(HorrorColors.crimson),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
