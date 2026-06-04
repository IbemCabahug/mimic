// lib/multiplayer/screens/multiplayer_menu_screen.dart
//
// Entry point for Mimic multiplayer mode. Presents Host and Join options
// in the horror theme. Detects active sessions and offers rejoin flow.
//
// ZERO vault imports — this screen is entirely within the game layer.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/screens/host_screen.dart';
import 'package:mimic/multiplayer/screens/join_screen.dart';
import 'package:mimic/multiplayer/screens/rejoin_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MultiplayerMenuScreen
// ═══════════════════════════════════════════════════════════════════════════

class MultiplayerMenuScreen extends ConsumerStatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  ConsumerState<MultiplayerMenuScreen> createState() =>
      _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends ConsumerState<MultiplayerMenuScreen>
    with SingleTickerProviderStateMixin {
  // ─── Name persistence ─────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  SharedPreferences? _prefs;

  // ─── Active session detection ─────────────────────────────────────────
  bool _hasActiveSession = false;
  String? _storedRoomCode;
  String? _storedPlayerName;
  String? _storedPlayerId;

  // ─── Entrance animation ───────────────────────────────────────────────
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedState();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ─── Persistence helpers ──────────────────────────────────────────────

  Future<void> _loadSavedState() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final savedName = _prefs?.getString('multiplayer_codename');
      _storedRoomCode = _prefs?.getString('last_room_code');
      _storedPlayerName = _prefs?.getString('last_player_name');
      _storedPlayerId = _prefs?.getString('last_player_id');

      if (!mounted) return;

      setState(() {
        if (savedName != null && savedName.isNotEmpty) {
          _nameController.text = savedName;
        } else {
          final randomNum = math.Random().nextInt(900) + 100;
          _nameController.text = 'Survivor #$randomNum';
        }

        // Detect active session from provider
        final netService = ref.read(networkServiceProvider);
        _hasActiveSession = netService.isConnected;
      });
    } catch (_) {
      final randomNum = math.Random().nextInt(900) + 100;
      _nameController.text = 'Survivor #$randomNum';
    }
  }

  Future<void> _saveName(String name) async {
    if (_prefs != null) {
      await _prefs!.setString('multiplayer_codename', name);
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────

  void _onHostPressed() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    _saveName(name);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HostScreen(hostName: name),
      ),
    );
  }

  void _onJoinPressed() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    _saveName(name);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const JoinScreen(),
      ),
    );
  }

  void _onRejoinPressed() {
    if (_storedRoomCode == null ||
        _storedPlayerName == null ||
        _storedPlayerId == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RejoinScreen(
          lastRoomCode: _storedRoomCode!,
          lastPlayerName: _storedPlayerName!,
          lastPlayerId: _storedPlayerId!,
        ),
      ),
    );
  }

  void _onNewGamePressed() {
    ref.read(networkServiceProvider).disconnect();
    setState(() {
      _hasActiveSession = false;
    });
  }

  void _dismissBanner() {
    setState(() {
      _hasActiveSession = false;
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Re-check connection status on rebuild
    final netService = ref.watch(networkServiceProvider);
    final isConnected = netService.isConnected;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: HorrorColors.crimson),
      ),
      body: StaticOverlay(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header: Animated title ──────────────────────
                        _buildHeader(),
                        const SizedBox(height: 36),

                        // ── Active session banner ───────────────────────
                        if (isConnected || _hasActiveSession)
                          _buildActiveSessionBanner(),

                        // ── Codename input ──────────────────────────────
                        _buildCodenameInput(),
                        const SizedBox(height: 36),

                        // ── CREATE ROOM card ────────────────────────────
                        _MenuCard(
                          icon: Icons.sports_esports,
                          iconColor: HorrorColors.crimson,
                          iconBgColor: HorrorColors.bloodRed,
                          title: 'Create Room',
                          subtitle: 'Host a game for your friends',
                          borderColor: HorrorColors.crimson,
                          onTap: _onHostPressed,
                        ),
                        const SizedBox(height: 16),

                        // ── JOIN ROOM card ──────────────────────────────
                        _MenuCard(
                          icon: Icons.visibility,
                          iconColor: HorrorColors.ashGray,
                          iconBgColor: HorrorColors.cardSurface,
                          title: 'Join Room',
                          subtitle: 'Enter a code or scan QR',
                          borderColor: HorrorColors.darkRedTint,
                          onTap: _onJoinPressed,
                        ),
                        const SizedBox(height: 48),

                        // ── Disguise footer ─────────────────────────────
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        // Large flickering MIMIC title
        FlickerWidget(
          child: Text(
            'MIMIC',
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 64,
              letterSpacing: 6.0,
              shadows: [
                Shadow(
                  color: HorrorColors.crimson.withValues(alpha: 0.5),
                  blurRadius: 25,
                ),
                Shadow(
                  color: HorrorColors.bloodRed.withValues(alpha: 0.3),
                  blurRadius: 50,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        Text(
          'M U L T I P L A Y E R',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: HorrorColors.ashGray,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 6.0,
          ),
        ),
        const SizedBox(height: 12),

        // Thin divider line
        Container(
          height: 1,
          width: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                HorrorColors.crimson.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Codename input ───────────────────────────────────────────────────

  Widget _buildCodenameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR CODENAME',
          style: GoogleFonts.creepster(
            color: HorrorColors.fogWhite,
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          style: GoogleFonts.inter(color: HorrorColors.fogWhite),
          cursorColor: HorrorColors.crimson,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Codenames cannot be empty';
            }
            if (value.length > 12) {
              return 'Keep it under 12 characters';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: 'Enter Codename',
            hintStyle: GoogleFonts.inter(color: HorrorColors.ashGray),
            prefixIcon: const Icon(
              Icons.person_outline,
              color: HorrorColors.ashGray,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Active session banner ────────────────────────────────────────────

  Widget _buildActiveSessionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HorrorColors.deepSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: HorrorColors.crimson.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HeartbeatPulse(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: HorrorColors.crimson,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Active session detected',
                  style: GoogleFonts.inter(
                    color: HorrorColors.fogWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _dismissBanner,
                child: Icon(
                  Icons.close,
                  color: HorrorColors.ashGray.withValues(alpha: 0.6),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _BannerButton(
                  label: 'REJOIN',
                  backgroundColor: HorrorColors.bloodRed,
                  borderColor: HorrorColors.crimson,
                  textColor: HorrorColors.fogWhite,
                  onTap: _onRejoinPressed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BannerButton(
                  label: 'NEW GAME',
                  backgroundColor: HorrorColors.cardSurface,
                  borderColor: HorrorColors.ashGray.withValues(alpha: 0.3),
                  textColor: HorrorColors.ashGray,
                  onTap: _onNewGamePressed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          height: 1,
          width: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                HorrorColors.ashGray.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Up to 8 players  •  No internet required  •  Same network',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: HorrorColors.ashGray.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _MenuCard — pressable card with scale + glow feedback
// ═══════════════════════════════════════════════════════════════════════════

class _MenuCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final Color borderColor;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.borderColor,
    required this.onTap,
  });

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _pressController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _isPressed
                ? HorrorColors.deepSurface
                : HorrorColors.cardSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.borderColor,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.borderColor.withValues(
                  alpha: _isPressed ? 0.25 : 0.1,
                ),
                blurRadius: _isPressed ? 18 : 10,
                spreadRadius: _isPressed ? 1 : 0,
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.iconBgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.borderColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.iconColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.creepster(
                        color: widget.borderColor == HorrorColors.crimson
                            ? HorrorColors.crimson
                            : HorrorColors.fogWhite,
                        fontSize: 22,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        color: HorrorColors.ashGray,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right,
                color: widget.borderColor == HorrorColors.crimson
                    ? HorrorColors.crimson
                    : HorrorColors.ashGray,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BannerButton — compact button used inside the active session banner
// ═══════════════════════════════════════════════════════════════════════════

class _BannerButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  const _BannerButton({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 2,
          shadowColor: borderColor.withValues(alpha: 0.3),
          side: BorderSide(color: borderColor, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: GoogleFonts.creepster(
            fontSize: 14,
            letterSpacing: 1.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
