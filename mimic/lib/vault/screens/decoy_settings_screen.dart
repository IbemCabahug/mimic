// mimic/lib/vault/screens/decoy_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../security/decoy_vault_service.dart';

class DecoySettingsScreen extends ConsumerStatefulWidget {
  const DecoySettingsScreen({super.key});

  @override
  ConsumerState<DecoySettingsScreen> createState() => _DecoySettingsScreenState();
}

class _DecoySettingsScreenState extends ConsumerState<DecoySettingsScreen> {
  bool _biometricsEnabled = false;
  String _idleTimeout = '2 minutes';

  void _changeDecoyPin() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Change Vault PIN',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
              color: VaultColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(labelText: 'New PIN', counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(labelText: 'Confirm PIN', counterText: ''),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: VaultColors.error, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final pin = pinController.text;
                final confirm = confirmController.text;
                if (pin.length < 4) {
                  setDialogState(() => error = 'PIN must be at least 4 digits');
                  return;
                }
                if (pin != confirm) {
                  setDialogState(() => error = 'PINs do not match');
                  return;
                }
                await ref.read(decoyVaultServiceProvider).setDecoyPin(pin);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PIN changed successfully'),
                      backgroundColor: VaultColors.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: VaultColors.accent),
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );
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
          'Vault Settings',
          style: TextStyle(
            color: VaultColors.accent,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VaultColors.accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Security',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: VaultColors.accent,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _buildTile(
            icon: Icons.pin,
            title: 'Change PIN',
            subtitle: 'Update your numeric unlock code',
            onTap: _changeDecoyPin,
          ),
          _buildTile(
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: 'Unlock vault with fingerprint or face',
            trailing: Switch(
              value: _biometricsEnabled,
              activeThumbColor: VaultColors.accent,
              onChanged: (val) => setState(() => _biometricsEnabled = val),
            ),
          ),
          _buildTile(
            icon: Icons.timer_outlined,
            title: 'Auto-Lock when idle',
            subtitle: _idleTimeout,
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Auto-Lock Timeout'),
                  children: ['1 minute', '2 minutes', '5 minutes', '10 minutes'].map((t) {
                    return SimpleDialogOption(
                      onPressed: () {
                        setState(() => _idleTimeout = t);
                        Navigator.of(ctx).pop();
                      },
                      child: Text(t),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Storage',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: VaultColors.accent,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _buildTile(
            icon: Icons.pie_chart_outline,
            title: 'Vault Storage',
            subtitle: '28.4 MB encrypted files stored locally',
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _lockVault,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Lock Vault Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: VaultColors.accent),
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: VaultColors.textPrimary,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: VaultColors.textSecondary,
                  ),
                )
              : null,
          trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: VaultColors.textTertiary) : null),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
