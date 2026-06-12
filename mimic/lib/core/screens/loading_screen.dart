import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with TickerProviderStateMixin {
  late AnimationController _bgGlowController;
  late AnimationController _entryController;
  late Animation<double> _bgGlowAnimation;
  
  late Timer _taglineTimer;
  late Timer _glitchTimer;
  
  int _taglineIndex = 0;
  double _glitchOffset = 0.0;
  bool _isGlitching = false;

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

    // Background breathing glow
    _bgGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _bgGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _bgGlowController, curve: Curves.easeInOut),
    );

    // Entry fade + scale for MIMIC wordmark
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    // Rotating tagline
    _taglineTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (mounted) {
        setState(() {
          _taglineIndex = (_taglineIndex + 1) % _taglines.length;
        });
      }
    });

    // Subtle glitch effect every ~3 seconds
    _glitchTimer = Timer.periodic(const Duration(milliseconds: 3100), (timer) async {
      if (!mounted) return;
      setState(() {
        _isGlitching = true;
        _glitchOffset = 4.0; // Shift right
      });
      
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      
      setState(() {
        _glitchOffset = -3.0; // Shift left
      });
      
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      
      setState(() {
        _isGlitching = false;
        _glitchOffset = 0.0;
      });
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
    _bgGlowController.dispose();
    _entryController.dispose();
    _taglineTimer.cancel();
    _glitchTimer.cancel();
    super.dispose();
  }

  // TODO: swap this gradient for Image.asset('assets/splash/splash_scene.png') with BoxFit.cover
  // once the illustrated splash art is added (keep a dark gradient overlay on top for legibility).
  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _bgGlowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F14),
            gradient: RadialGradient(
              center: Alignment.bottomCenter,
              radius: 1.2,
              colors: [
                HorrorColors.crimson.withValues(alpha: _bgGlowAnimation.value * 0.5),
                const Color(0xFF0F0F14).withValues(alpha: 0.9),
                const Color(0xFF0F0F14),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Container(
            // Dark vignette around edges
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordmark() {
    final textStyle = GoogleFonts.creepster(
      color: Colors.white,
      fontSize: 64,
      letterSpacing: 12.0,
      shadows: [
        BoxShadow(
          color: HorrorColors.crimson.withValues(alpha: 0.8),
          blurRadius: 30,
          spreadRadius: 10,
        ),
      ],
    );

    return ScaleTransition(
      scale: Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(
        opacity: _entryController,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glitch layer (crimson duplicate)
            if (_isGlitching)
              Transform.translate(
                offset: Offset(_glitchOffset, 0),
                child: Text(
                  'MIMIC',
                  style: textStyle.copyWith(
                    color: HorrorColors.crimson.withValues(alpha: 0.6),
                  ),
                ),
              ),
            // Base layer
            Text(
              'MIMIC',
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          _buildBackground(),
          
          // Foreground Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                
                // Animated Wordmark
                _buildWordmark(),
                
                const SizedBox(height: 40),
                
                // Rotating Tagline
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _taglines[_taglineIndex],
                    key: ValueKey<int>(_taglineIndex),
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.5,
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
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
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
