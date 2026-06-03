import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../crypto/vault_crypto.dart';
import '../../core/services/platform_service.dart';
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {

  void _lockVault() {
    final crypto = ref.read(vaultCryptoProvider);
    crypto.lock();
    PanicMode().dispose();
    AutoLock().dispose();
    Navigator.of(context).pushNamedAndRemoveUntil('/vault-pin', (route) => false);
  }

  void _showChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Change PIN',
            style: TextStyle(
              color: VaultColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPinField(currentPinController, 'Current PIN'),
              const SizedBox(height: 12),
              _buildPinField(newPinController, 'New PIN'),
              const SizedBox(height: 12),
              _buildPinField(confirmPinController, 'Confirm New PIN'),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: VaultColors.error, fontSize: 13, fontFamily: 'Inter'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: () async {
                final newPin = newPinController.text;
                final confirmPin = confirmPinController.text;

                if (newPin.length < 4) {
                  setDialogState(() => error = 'New PIN must be at least 4 digits');
                  return;
                }
                if (newPin != confirmPin) {
                  setDialogState(() => error = 'PINs do not match');
                  return;
                }

                // Re-initialize with the new PIN
                try {
                  final crypto = ref.read(vaultCryptoProvider);
                  crypto.lock();
                  final platformService = ref.read(platformServiceProvider);
                  // Clear old PIN data
                  await platformService.secureDelete('vault_salt');
                  await platformService.secureDelete('vault_pin_hash');
                  if (!kIsWeb) {
                    await platformService.secureWrite('vault_pin', newPin);
                  }
                  await crypto.initialize(newPin);

                  if (context.mounted && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('PIN changed successfully'),
                        backgroundColor: VaultColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(() => error = 'Failed to change PIN: $e');
                }
              },
              child: const Text(
                'Change',
                style: TextStyle(color: VaultColors.accent, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
      style: const TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
        counterText: '',
        filled: true,
        fillColor: VaultColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VaultColors.accent),
        ),
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear All Vault Data',
          style: TextStyle(
            color: VaultColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
        content: const Text(
          'This will permanently delete all encrypted files, notes, audio recordings, and break-in logs. This action cannot be undone.',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final platformService = ref.read(platformServiceProvider);
              await platformService.secureDelete('break_in_logs');
              await platformService.secureDelete('vault_photos_meta');
              await platformService.secureDelete('vault_audio_meta');
              await platformService.secureDelete('vault_notes');
              
              // Wiping sqflite breakin logs database
              try {
                final dbPath = p.join(await getDatabasesPath(), 'breakin_logs.db');
                final file = File(dbPath);
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (_) {}

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('All vault data cleared'),
                    backgroundColor: VaultColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: const Text(
              'Delete Everything',
              style: TextStyle(color: VaultColors.error, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Settings',
      showLockButton: false,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // Security Section
          _buildSectionHeader('Security'),
          _buildSettingsTile(
            icon: Icons.lock_outline,
            title: 'Change PIN',
            subtitle: 'Update your vault access PIN',
            onTap: _showChangePinDialog,
          ),
          _buildSettingsTile(
            icon: Icons.lock,
            title: 'Lock Vault',
            subtitle: 'Lock vault and return to PIN screen',
            onTap: _lockVault,
            iconColor: VaultColors.error,
          ),

          const SizedBox(height: 24),

          // Security Auditing Section
          _buildSectionHeader('Auditing'),
          _buildSettingsTile(
            icon: Icons.shield_outlined,
            title: 'Intruder Logs',
            subtitle: 'View failed PIN attempts and photo captures',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-breakin-logs');
            },
          ),

          const SizedBox(height: 24),

          // Danger Zone
          _buildSectionHeader('Danger Zone'),
          _buildSettingsTile(
            icon: Icons.delete_forever,
            title: 'Clear All Data',
            subtitle: 'Delete all encrypted files and notes',
            onTap: _showClearDataDialog,
            iconColor: VaultColors.error,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: VaultColors.textTertiary,
          fontFamily: 'Inter',
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = VaultColors.accent,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: VaultColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: VaultColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: VaultColors.textTertiary, size: 20),
        onTap: onTap,
      ),
    );
  }
}
