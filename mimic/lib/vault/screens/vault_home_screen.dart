import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../crypto/vault_crypto.dart';
import '../services/file_vault_service.dart';
import '../services/notes_service.dart';
import '../services/video_vault_service.dart';
import '../services/document_vault_service.dart';
import '../services/backup_reminder_service.dart';
import '../widgets/vault_scaffold.dart';
import '../security/shake_wipe_service.dart';
import '../widgets/blood_splatter_overlay.dart';
import '../widgets/backup_out_of_date_banner.dart';

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late final ShakeWipeService _shakeWipeService;
  Timer? _reminderTimer;
  int _photoCount = 0;
  int _noteCount = 0;
  int _videoCount = 0;
  int _documentCount = 0;
  bool _isHiding = false;

  @override
  void initState() {
    super.initState();
    _shakeWipeService = ref.read(shakeWipeServiceProvider);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _loadCounts();
    _setupShakeListener();

    _reminderTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        BackupReminderService.checkAndShowReminder(context);
      }
    });
  }

  Future<void> _setupShakeListener() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final shakeEnabled = prefs.getBool('shake_wipe_enabled') ?? false;
    if (shakeEnabled && mounted) {
      _shakeWipeService.startListening(() {
        _handleShakeToHide();
      });
    }
  }

  void _handleShakeToHide() {
    if (!mounted) return;
    setState(() {
      _isHiding = true;
    });

    // Capture the root overlay state BEFORE pushNamedAndRemoveUntil disposes this screen
    final overlay = Navigator.of(context, rootNavigator: true).overlay;

    // Lock the vault in memory
    ref.read(vaultCryptoProvider).clearKey();

    // Navigate to the game home on the root navigator
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/', (r) => false);

    // Trigger the blood-splatter cue on the root overlay
    if (overlay != null) {
      showBloodSplatter(overlay);
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _shakeWipeService.stopListening();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final photos = await ref.read(fileVaultServiceProvider).getAllPhotos();
      final notes = await ref.read(notesServiceProvider).getAllNotes();
      final videos = await ref.read(videoVaultServiceProvider).getAllVideos();
      final documents = await ref.read(documentVaultServiceProvider).listDocuments();
      if (mounted) {
        setState(() {
          _photoCount = photos.length;
          _noteCount = notes.length;
          _videoCount = videos.length;
          _documentCount = documents.length;
        });
      }
    } catch (_) {
      // Silently handle - counts stay at 0
    }
  }

  @override
  Widget build(BuildContext context) {
    final crypto = ref.watch(vaultCryptoProvider);
    if (!crypto.isUnlocked && !_isHiding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/vault-pin');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return VaultScaffold(
      title: null,
      showBackButton: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: VaultColors.accent),
          onPressed: () async {
            await Navigator.of(context).pushNamed('/vault-settings');
            // Reload counts when returning from settings (data might be cleared)
            _loadCounts();
          },
          tooltip: 'Settings',
        ),
      ],
      body: Stack(
        children: [
          // Decorative background elements
          Positioned(
            right: -40,
            bottom: -40,
            child: Icon(
              Icons.lock_outline,
              size: 200,
              color: VaultColors.accent.withValues(alpha: 0.04),
            ),
          ),
          Positioned(
            left: -30,
            top: 100,
            child: Icon(
              Icons.lock,
              size: 140,
              color: VaultColors.accent.withValues(alpha: 0.03),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BackupOutOfDateBanner(),
                  // Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Text(
                      'My Vault',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: VaultColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 32,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Your encrypted files are safe here',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VaultColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Section grid
                  Expanded(
                    child: GridView.count(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        _VaultSectionCard(
                          title: 'Photos',
                          icon: Icons.photo_outlined,
                          color: const Color(0xFF534AB7),
                          count: _photoCount,
                          onTap: () async {
                            await Navigator.of(
                              context,
                            ).pushNamed('/vault-photos');
                            _loadCounts();
                          },
                        ),
                        _VaultSectionCard(
                          title: 'Notes',
                          icon: Icons.note_outlined,
                          color: const Color(0xFF1D9E75),
                          count: _noteCount,
                          onTap: () async {
                            await Navigator.of(
                              context,
                            ).pushNamed('/vault-notes');
                            _loadCounts();
                          },
                        ),
                        _VaultSectionCard(
                          title: 'Videos',
                          icon: Icons.video_library_outlined,
                          color: const Color(0xFF8E24AA),
                          count: _videoCount,
                          onTap: () async {
                            await Navigator.of(
                              context,
                            ).pushNamed('/vault-videos');
                            _loadCounts();
                          },
                        ),
                        _VaultSectionCard(
                          title: 'Documents',
                          icon: Icons.description_outlined,
                          color: const Color(0xFF378ADD),
                          count: _documentCount,
                          onTap: () async {
                            await Navigator.of(
                              context,
                            ).pushNamed('/vault-documents');
                            _loadCounts();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  const _VaultSectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: VaultColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count item${count != 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 13,
              color: VaultColors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
