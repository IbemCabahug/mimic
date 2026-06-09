// mimic/lib/vault/screens/vault_settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../crypto/vault_crypto.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/stealth_mode_service.dart';
import '../../core/services/launcher_icon_service.dart';
import '../../core/theme/app_theme.dart';
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../services/biometric_service.dart';
import '../widgets/vault_scaffold.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  bool _hasRecoveryBlob = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isLoadingBiometric = false;
  bool _shakeEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkRecoveryBlob();
    _checkBiometricState();
    _loadShakePref();
  }

  Future<void> _loadShakePref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _shakeEnabled = prefs.getBool('shake_wipe_enabled') ?? false);
    }
  }

  Future<void> _checkRecoveryBlob() async {
    final platformService = ref.read(platformServiceProvider);
    final blob = await platformService.secureRead('recovery_blob');
    if (mounted) {
      setState(() {
        _hasRecoveryBlob = blob != null && blob.isNotEmpty;
      });
    }
  }

  Future<void> _checkBiometricState() async {
    final biometricService = BiometricService();
    final available = await biometricService.isBiometricAvailable();
    final enabled = await biometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _onBiometricToggle(bool value) async {
    if (!_biometricAvailable) return;
    final biometricService = BiometricService();
    if (value) {
      setState(() => _isLoadingBiometric = true);
      final success = await biometricService.authenticate();
      if (mounted) {
        setState(() => _isLoadingBiometric = false);
      }
      if (success && mounted) {
        await biometricService.setBiometricEnabled(true);
        setState(() => _biometricEnabled = true);
      }
    } else {
      await biometricService.setBiometricEnabled(false);
      if (mounted) {
        setState(() => _biometricEnabled = false);
      }
    }
  }

  Future<void> _onShakeToggle(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Are you sure?',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter'),
          ),
          content: const Text(
            'If you shake and have lost your 12-word recovery phrase, your vault cannot be recovered. Make sure your recovery phrase is safely backed up before enabling this.',
            style: TextStyle(fontFamily: 'Inter'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enable', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('shake_wipe_enabled', true);
        if (mounted) {
          setState(() => _shakeEnabled = true);
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shake_wipe_enabled', false);
      if (mounted) {
        setState(() => _shakeEnabled = false);
      }
    }
  }

  Future<void> _onHideAppIconToggle(bool hide) async {
    if (hide) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Hide app icon?',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter'),
          ),
          content: const Text(
            "Mimic's icon will disappear from your home screen and app drawer. To reopen it, go to Android Settings > Apps > Mimic > Open, then turn this off again. Continue?",
            style: TextStyle(fontFamily: 'Inter'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hide', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        ref.read(launcherIconProvider.notifier).setIconVisible(false);
      }
    } else {
      ref.read(launcherIconProvider.notifier).setIconVisible(true);
    }
  }

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

                try {
                  final crypto = ref.read(vaultCryptoProvider);
                  crypto.lock();
                  final platformService = ref.read(platformServiceProvider);
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
    final bool stealth = ref.watch(stealthModeProvider);
    final bool iconVisible = ref.watch(launcherIconProvider);

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
            icon: Icons.vpn_key_outlined,
            title: 'Recovery Phrase',
            subtitle: _hasRecoveryBlob
                ? 'Recovery phrase is set up'
                : 'Set up a 12-word backup to recover vault access',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-recovery-phrase');
            },
            trailing: _hasRecoveryBlob
                ? const Icon(Icons.check_circle, color: VaultColors.success, size: 20)
                : null,
          ),
          _buildSettingsTile(
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: _biometricAvailable
                ? 'Use fingerprint or face to access your vault'
                : 'Not available on this device',
            onTap: _biometricAvailable && !_isLoadingBiometric ? () {
              if (_biometricEnabled) {
                _onBiometricToggle(false);
              } else {
                _onBiometricToggle(true);
              }
            } : null,
              trailing: !_isLoadingBiometric && _biometricAvailable
                  ? Switch(
                      value: _biometricEnabled,
                      onChanged: (value) => _onBiometricToggle(value),
                      activeThumbColor: VaultColors.accent,
                    )
                : _isLoadingBiometric
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: VaultColors.accent),
                      )
                    : null,
          ),
          _buildSettingsTile(
            icon: Icons.admin_panel_settings,
            title: 'Duress PIN',
            subtitle: 'Fake PIN that opens the admin panel instead of your vault',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-set-duress-pin');
            },
          ),
          _buildSettingsTile(
            icon: Icons.vibration,
            title: 'Shake to Wipe',
            subtitle: 'Double shake instantly hides your vault until restored',
            onTap: () {},
            trailing: Switch(
              value: _shakeEnabled,
              onChanged: (value) => _onShakeToggle(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.visibility_off,
            title: 'Stealth Mode',
            subtitle: 'Hides all vault hints across the game. Secret unlock patterns still work.',
            onTap: null,
            trailing: Switch(
              value: stealth,
              onChanged: (value) => ref.read(stealthModeProvider.notifier).setStealthMode(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.visibility_off,
            title: 'Hide App Icon',
            subtitle: 'Removes Mimic from the app drawer. Reopen via Android Settings > Apps > Mimic > Open.',
            onTap: null,
            trailing: Switch(
              value: !iconVisible,
              onChanged: (value) => _onHideAppIconToggle(value),
              activeThumbColor: VaultColors.accent,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.lock,
            title: 'Lock Vault',
            subtitle: 'Lock vault and return to PIN screen',
            onTap: _lockVault,
            iconColor: VaultColors.error,
          ),

          const SizedBox(height: 24),

          // Backup Section
          _buildSectionHeader('Backup'),
          _buildSettingsTile(
            icon: Icons.upload_outlined,
            title: 'Export Vault',
            subtitle: 'Save an encrypted backup of your vault',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-export');
            },
          ),
          _buildSettingsTile(
            icon: Icons.download_outlined,
            title: 'Import Vault',
            subtitle: 'Restore vault from a .mimic backup file',
            onTap: () {
              Navigator.of(context).pushNamed('/vault-import');
            },
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
    required VoidCallback? onTap,
    Color iconColor = VaultColors.accent,
    Widget? trailing,
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
      child: Material(
        color: Colors.transparent,
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
          trailing: trailing ?? const Icon(Icons.chevron_right, color: VaultColors.textTertiary, size: 20),
          onTap: onTap,
        ),
      ),
    );
  }
}
