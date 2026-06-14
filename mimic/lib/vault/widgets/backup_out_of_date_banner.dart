import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/theme/app_theme.dart';
import '../services/vault_backup_status.dart';
import '../export/vault_exporter.dart';
import '../services/file_vault_service.dart';
import '../services/notes_service.dart';
import '../services/video_vault_service.dart';
import '../services/document_vault_service.dart';

class BackupOutOfDateBanner extends ConsumerStatefulWidget {
  const BackupOutOfDateBanner({super.key});

  @override
  ConsumerState<BackupOutOfDateBanner> createState() => _BackupOutOfDateBannerState();
}

class _BackupOutOfDateBannerState extends ConsumerState<BackupOutOfDateBanner> {
  bool _isOutOfDate = false;
  bool _isUpdating = false;
  VaultBackupStatus? _status;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await VaultBackupStatus.init();
    final photos = await ref.read(fileVaultServiceProvider).getAllPhotos();
    final notes = await ref.read(notesServiceProvider).getAllNotes();
    final videos = await ref.read(videoVaultServiceProvider).getAllVideos();
    final documents = await ref.read(documentVaultServiceProvider).listDocuments();
    
    final total = photos.length + notes.length + videos.length + documents.length;
    if (mounted) {
      setState(() {
        _status = status;
        _isOutOfDate = status.isBackupOutOfDate(total);
      });
    }
  }

  Future<void> _updateBackup() async {
    setState(() => _isUpdating = true);
    try {
      final filename = _status?.lastExportFilename;
      await VaultExporter.buildExportFile(ref, overwritePath: filename);
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOutOfDate) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VaultColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VaultColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: VaultColors.error, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Backup out of date',
                  style: TextStyle(
                    color: VaultColors.error,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Backup out of date — you've added items since your last backup.",
            style: TextStyle(
              color: VaultColors.error.withValues(alpha: 0.9),
              fontSize: 13,
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isUpdating ? null : _updateBackup,
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Update backup'),
          ),
        ],
      ),
    );
  }
}
