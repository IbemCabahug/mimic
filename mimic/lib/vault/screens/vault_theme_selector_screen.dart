// mimic/lib/vault/screens/vault_theme_selector_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../services/pro_status_service.dart';
import '../services/vault_theme_service.dart';
import '../widgets/paywall_sheet.dart';

class VaultThemeSelectorScreen extends ConsumerWidget {
  const VaultThemeSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPalette = ref.watch(vaultThemeProvider);
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: currentPalette.background,
      appBar: AppBar(
        title: Text(
          'Vault Themes',
          style: TextStyle(
            color: currentPalette.accent,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: currentPalette.accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Personalize your vault interface with custom stealth palettes.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: currentPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ...VaultThemeService.allThemes.map((theme) {
            final isSelected = theme.id == currentPalette.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? theme.accent : Colors.black.withValues(alpha: 0.08),
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () async {
                  if (theme.isProOnly && !isPro) {
                    showPaywallSheet(context);
                    return;
                  }
                  final ok = await ref.read(vaultThemeProvider.notifier).setTheme(theme.id, isPro: isPro);
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Applied theme: ${theme.name}'),
                        backgroundColor: VaultColors.success,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      // Swatch Preview
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: theme.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                        ),
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: theme.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Information
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  theme.name,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: theme.textPrimary,
                                  ),
                                ),
                                if (theme.isProOnly) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4AF37),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              theme.description,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: theme.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Check icon or Pro lock
                      if (isSelected)
                        Icon(Icons.check_circle, color: theme.accent, size: 26)
                      else if (theme.isProOnly && !isPro)
                        const Icon(Icons.lock_outline, color: VaultColors.textTertiary, size: 22)
                      else
                        const Icon(Icons.radio_button_unchecked, color: VaultColors.textTertiary, size: 22),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
