import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../crypto/vault_exceptions.dart';
import '../security/auto_lock.dart';
import '../services/background_import_service.dart';
import '../services/import_coordinator.dart';
import '../services/media_import_policy.dart';
import '../services/media_picker_adapter.dart';

/// Shared gallery import entry flow for both [PhotoVaultScreen] and
/// [VideoVaultScreen].
///
/// Handles the one-time warning dialog (including the 100-item per-batch limit
/// and multi-batch append note), protects gallery selection with a scoped
/// [AutoLockLease], and hands lightweight [MediaSourceRef] entries to the
/// app-scoped [ImportCoordinator] without retaining any UI context or callbacks.
Future<void> runGalleryImportFlow({
  required BuildContext context,
  required WidgetRef ref,
  required ImportMediaKind kind,
  required bool Function() isMounted,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final ack = prefs.getBool('import_move_warning_ack') ?? false;

  if (!ack && isMounted()) {
    bool dontShowAgain = false;
    final confirmed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Important Warning',
                style: TextStyle(
                  color: VaultColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Media originals are REMOVED from the gallery and are permanently lost if the app is uninstalled or its data is cleared before restoring — back up via Settings → Export and keep the 12-word recovery phrase.',
                    style: TextStyle(
                      color: VaultColors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    kMediaImportLimitBanner,
                    style: TextStyle(
                      color: VaultColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Active imports continue in the background when you switch apps, while vault browsing locks automatically when you leave.',
                    style: TextStyle(
                      color: VaultColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: dontShowAgain,
                        onChanged: (val) {
                          setDialogState(() => dontShowAgain = val ?? false);
                        },
                        activeColor: VaultColors.accent,
                        side: const BorderSide(width: 2, color: Colors.black),
                      ),
                      const Expanded(
                        child: Text(
                          "Don't show again",
                          style: TextStyle(
                            color: VaultColors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: VaultColors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      await prefs.setBool('import_move_warning_ack', true);
                    }
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      color: VaultColors.accent,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
  }

  if (!isMounted()) return;

  final lease = AutoLock().acquireProtectedOperation();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final picker = ref.read(mediaPickerAdapterProvider);
    final coordinator = ref.read(importCoordinatorProvider);
    final bgBridge = ref.read(backgroundImportBridgeProvider);
    final selected = await picker.pickAssets(
      context,
      kind: kind,
      maxAssets: MediaImportPolicy.maxAssetsPerBatch,
    );
    if (selected == null || selected.isEmpty) return;

    final hadNotif = await bgBridge.hasNotificationPermission();
    bool notifGranted = hadNotif;
    if (!hadNotif) {
      notifGranted = await bgBridge.requestNotificationPermission();
    }

    await coordinator.enqueueBatch(
      sources: selected,
      scope: const VaultImportScope(),
    );

    if (!notifGranted && isMounted() && messenger != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are disabled — background import status will not appear in the notification shade.',
          ),
        ),
      );
    }
  } catch (e) {
    if (isMounted() && messenger != null) {
      final msg = formatGalleryImportError(kind, e);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  } finally {
    lease.release();
  }
}

String formatGalleryImportError(ImportMediaKind kind, Object? error) {
  final nounPlural = kind == ImportMediaKind.photo ? 'photos' : 'videos';
  final nounSingle = kind == ImportMediaKind.photo ? 'a photo' : 'a video';
  final errStr = error?.toString() ?? '';
  final isLocked =
      errStr.contains('Vault is locked') || errStr.contains('locked');
  final isDamaged =
      error is CorruptedMediaFileException ||
      errStr.contains('damaged') ||
      errStr.contains('corrupted');

  if (isLocked) {
    return 'Could not import $nounPlural: the vault is locked.';
  }
  if (isDamaged) {
    return 'Failed to import $nounPlural: $nounSingle is damaged or unsupported.';
  }
  return 'Failed to import $nounPlural: could not read $nounSingle.';
}
