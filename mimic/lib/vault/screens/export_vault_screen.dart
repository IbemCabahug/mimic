// lib/vault/screens/export_vault_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/theme/app_theme.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/backup_reminder_service.dart';
import 'package:mimic/vault/widgets/vault_scaffold.dart';
import 'package:mimic/vault/export/vault_exporter.dart';

class ExportVaultScreen extends ConsumerStatefulWidget {
  const ExportVaultScreen({super.key});

  @override
  ConsumerState<ExportVaultScreen> createState() => _ExportVaultScreenState();
}

class _ExportVaultScreenState extends ConsumerState<ExportVaultScreen> {
  bool _hasRecoveryBlob = false;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _checkRecoveryBlob();
  }

  Future<void> _checkRecoveryBlob() async {
    try {
      final platformService = ref.read(platformServiceProvider);
      final blob = await platformService.secureRead('recovery_blob');
      if (mounted) {
        setState(() {
          _hasRecoveryBlob = blob != null && blob.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasRecoveryBlob = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportToDownloads() async {
    setState(() => _isExporting = true);
    try {
      final file = await VaultExporter.buildExportFile();
      await BackupReminderService.markBackupCompleted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backup saved to: ${file.path}',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            backgroundColor: VaultColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export failed: $e',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            backgroundColor: VaultColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportAndShare() async {
    setState(() => _isExporting = true);
    try {
      final file = await VaultExporter.buildExportFile();
      await BackupReminderService.markBackupCompleted();
      await VaultExporter.shareFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export & Share failed: $e',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            backgroundColor: VaultColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Export Vault',
      showLockButton: false,
      body: Stack(
        children: [
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: VaultColors.accent),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      const SizedBox(height: 24),
                      const Icon(
                        Icons.unarchive_outlined,
                        color: VaultColors.accent,
                        size: 72,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Export Your Vault',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: VaultColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The export file is encrypted and contains all your encrypted notes, photos, and audio recordings. For security, it can only be opened and decrypted using your recovery phrase.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: VaultColors.textSecondary,
                          fontFamily: 'Inter',
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildWarningCard(),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed: (_hasRecoveryBlob && !_isExporting) ? _exportToDownloads : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VaultColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ).copyWith(
                          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return VaultColors.accent.withValues(alpha: 0.3);
                            }
                            return VaultColors.accent;
                          }),
                        ),
                        child: const Text(
                          'Save to Downloads',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: (_hasRecoveryBlob && !_isExporting) ? _exportAndShare : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VaultColors.accent,
                          side: const BorderSide(color: VaultColors.accent),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ).copyWith(
                          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return BorderSide(color: VaultColors.accent.withValues(alpha: 0.3));
                            }
                            return const BorderSide(color: VaultColors.accent);
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return VaultColors.accent.withValues(alpha: 0.3);
                            }
                            return VaultColors.accent;
                          }),
                        ),
                        child: const Text(
                          'Save & Share',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_isExporting)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: VaultColors.accent),
                    SizedBox(height: 16),
                    Text(
                      'Exporting Vault...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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

  Widget _buildWarningCard() {
    if (!_hasRecoveryBlob) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VaultColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VaultColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: VaultColors.error, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WARNING',
                    style: TextStyle(
                      color: VaultColors.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: 'Inter',
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Make sure your recovery phrase is set up before exporting',
                    style: TextStyle(
                      color: VaultColors.error.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VaultColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VaultColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: VaultColors.success, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STATUS',
                    style: TextStyle(
                      color: VaultColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: 'Inter',
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Recovery phrase is set up ✓',
                    style: TextStyle(
                      color: VaultColors.success,
                      fontSize: 13,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}
