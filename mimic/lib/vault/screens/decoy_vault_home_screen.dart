// mimic/lib/vault/screens/decoy_vault_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../security/decoy_vault_service.dart';
import '../services/pro_status_service.dart';

class DecoyVaultHomeScreen extends ConsumerStatefulWidget {
  const DecoyVaultHomeScreen({super.key});

  @override
  ConsumerState<DecoyVaultHomeScreen> createState() => _DecoyVaultHomeScreenState();
}

class _DecoyVaultHomeScreenState extends ConsumerState<DecoyVaultHomeScreen> {
  int _photoCount = 0;
  int _noteCount = 0;
  int _docCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkProAccess();
    _loadCounts();
  }

  Future<void> _checkProAccess() async {
    final isPro = await ref.read(proStatusServiceProvider).isPro();
    if (!isPro && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRouter.homeRoute,
        (r) => false,
      );
    }
  }

  Future<void> _loadCounts() async {
    final service = ref.read(decoyVaultServiceProvider);
    final photos = await service.getPhotos();
    final notes = await service.getNotes();
    final docs = await service.getDocuments();
    if (mounted) {
      setState(() {
        _photoCount = photos.length;
        _noteCount = notes.length;
        _docCount = docs.length;
        _isLoading = false;
      });
    }
  }

  void _lockVault() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.homeRoute,
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: const Text(
          'SECURE VAULT',
          style: TextStyle(
            color: VaultColors.accent,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 18,
          ),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: VaultColors.accent),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).pushNamed('/decoy-settings');
              _loadCounts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline, color: VaultColors.accent),
            tooltip: 'Lock Vault',
            onPressed: _lockVault,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : RefreshIndicator(
              onRefresh: _loadCounts,
              color: VaultColors.accent,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  _buildVaultCard(
                    context,
                    title: 'Private Photos',
                    subtitle: '$_photoCount items stored',
                    icon: Icons.photo_library_outlined,
                    color: const Color(0xFF6750A4),
                    route: '/decoy-photos',
                  ),
                  const SizedBox(height: 16),
                  _buildVaultCard(
                    context,
                    title: 'Encrypted Notes',
                    subtitle: '$_noteCount private notes',
                    icon: Icons.description_outlined,
                    color: const Color(0xFF386A20),
                    route: '/decoy-notes',
                  ),
                  const SizedBox(height: 16),
                  _buildVaultCard(
                    context,
                    title: 'Secure Documents',
                    subtitle: '$_docCount documents',
                    icon: Icons.folder_outlined,
                    color: const Color(0xFF006874),
                    route: '/decoy-documents',
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VaultColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, color: VaultColors.accent, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Hardware Encryption Active',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: VaultColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'All contents secured with local encryption',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: VaultColors.textSecondary,
                                ),
                              ),
                            ],
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

  Widget _buildVaultCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).pushNamed(route);
          _loadCounts();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: VaultColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: VaultColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: VaultColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
