import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../security/vault_error_ui.dart';
import '../security/auto_lock.dart';
import '../crypto/vault_crypto.dart';
import '../services/file_vault_service.dart';
import '../widgets/vault_scaffold.dart';
import '../widgets/import_activity_button.dart';
import '../services/import_progress.dart';
import '../../core/theme/app_theme.dart';
import 'photo_viewer_screen.dart';

class PhotoVaultScreen extends ConsumerStatefulWidget {
  const PhotoVaultScreen({super.key});

  @override
  ConsumerState<PhotoVaultScreen> createState() => _PhotoVaultScreenState();
}

class _PhotoVaultScreenState extends ConsumerState<PhotoVaultScreen> {
  List<PhotoMeta> _photos = [];
  bool _isLoading = true;
  // Folder feature (mirrors DocumentVaultScreen): null = All, '' = Unfiled,
  // otherwise the folder name. Filter-only.
  String? _selectedFolder;
  // Multi-select: photo ids currently ticked. Empty set = selection mode off.
  final Set<String> _selection = {};
  // Live import card (mirrors Videos): per-photo Queued -> Encrypting N/M ->
  // delete-confirm wait -> Saved, so bulk imports never look dead — and a
  // single big photo cannot look like a frozen screen either.
  final ImportSession _importSession = ImportSession();

  /// Restore gets the SAME live pill + sheet the import flow has (one session
  /// per flow, like VideoVaultScreen): a batch restore is minutes of work, and
  /// the user must be able to see — and stop — it.
  final ImportSession _restoreSession = ImportSession();
  Timer? _restoreLingerTimer;
  // Keeps a settled card on screen ~4s so the outcome is seen, then clears it.
  // Cancellable: dispose() cancels it and the next import cancels it, so a
  // stale timer can never wipe a new session's rows.
  Timer? _lingerTimer;

  final LinkedHashMap<String, Uint8List> _bytesCache = LinkedHashMap();
  int _bytesCacheSize = 0;
  static const int _bytesCacheBudget = 32 * 1024 * 1024; // 32 MB

  Uint8List? _getCached(String id) {
    final b = _bytesCache.remove(id);
    if (b != null) _bytesCache[id] = b;
    return b;
  }

  void _putCached(String id, Uint8List b) {
    final old = _bytesCache.remove(id);
    if (old != null) _bytesCacheSize -= old.lengthInBytes;
    _bytesCache[id] = b;
    _bytesCacheSize += b.lengthInBytes;
    while (_bytesCacheSize > _bytesCacheBudget && _bytesCache.isNotEmpty) {
      final k = _bytesCache.keys.first;
      _bytesCacheSize -= _bytesCache.remove(k)!.lengthInBytes;
    }
  }

  Future<Uint8List?> _loadPhotoBytes(String id) async {
    final hit = _getCached(id);
    if (hit != null) return hit;
    Uint8List? bytes;
    try {
      bytes = await ref.read(fileVaultServiceProvider).getPhoto(id);
    } on SystemKeyMissingException catch (_) {
      if (!mounted) return null;
      showSecureKeyLostSnackBar(context);
      return null;
    }
    if (bytes != null) _putCached(id, bytes);
    return bytes;
  }

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    // The linger timer outlives the import flow by design, so it MUST be
    // cancelled here: otherwise it survives the screen and can fire against a
    // disposed session (and flutter_test flags it as a pending timer).
    _lingerTimer?.cancel();
    _restoreLingerTimer?.cancel();
    _bytesCache.clear();
    _bytesCacheSize = 0;
    _restoreSession.dispose();
    _importSession.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    final photos = await ref.read(fileVaultServiceProvider).getAllPhotos();
    if (mounted) {
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    }
  }

  Future<void> _importFromGallery() async {
    final prefs = await SharedPreferences.getInstance();
    final ack = prefs.getBool('import_move_warning_ack') ?? false;

    if (!ack && mounted) {
      bool dontShowAgain = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text(
                  'Important Warning',
                  style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Media originals are REMOVED from the gallery and are permanently lost if the app is uninstalled or its data is cleared before restoring — back up via Settings → Export and keep the 12-word recovery phrase.',
                      style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: dontShowAgain,
                          onChanged: (val) {
                            setState(() => dontShowAgain = val ?? false);
                          },
                          activeColor: VaultColors.accent,
                          // M3's unchecked border is a low-contrast grey that
                          // all but disappears on the white dialog — the
                          // operator reported exactly that. 2px black reads
                          // as a checkbox at a glance.
                          side: const BorderSide(width: 2, color: Colors.black),
                        ),
                        const Expanded(
                          child: Text(
                            "Don't show again",
                            style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (dontShowAgain) {
                        await prefs.setBool('import_move_warning_ack', true);
                      }
                      if (context.mounted) Navigator.of(context).pop(true);
                    },
                    child: const Text('Continue', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
                  ),
                ],
              );
            },
          );
        },
      );

      if (confirmed != true) return;
    }

    if (!mounted) return;
    AutoLock().beginProtectedOperation();
    var sessionActive = true;
    try {
      _lingerTimer?.cancel();
      _importSession.begin(const []);
      // Rows are addressed by the SERVICE's asset index, collected here as the
      // callback fires — never by counting result.successfulIds. A partial
      // failure makes those two orders differ, which would label the failed
      // file 'Saved' and the successful one 'Failed'.
      final savedRows = <int>[];
      final failedRows = <int, String>{};
      final result = await ref.read(fileVaultServiceProvider).pickAndEncryptImage(
        context,
        // The picker just reported the batch size: list the whole queue now.
        onPicked: (total) => _importSession.setTotal(total),
        onFileStart: (index, pos, name) {
          _importSession.ensureSlot(index, name);
          _importSession.markEncrypting(index, pos);
        },
        onFileSaved: (index) => savedRows.add(index),
        onFileFailed: (index, detail) => failedRows[index] = detail,
        onWaitingDeleteConfirm: () => _importSession.markWaitingDeleteConfirm(),
        // The pill's ✕ / the sheet's Cancel set this flag; the service checks
        // it before each NEXT file, so the in-flight photo always finishes.
        isCancelled: () => _importSession.cancelRequested,
      );
      sessionActive = false;
      // Outcome rows: per-photo Saved / Saved-original-kept. originalsKept ==
      // true means the source was left on the device (dialog denied, platform
      // refusal, or the delete phase never ran).
      for (final i in savedRows) {
        if (result.originalsKept) {
          _importSession.markSavedOriginalKept(i);
        } else {
          _importSession.markSaved(i);
        }
      }
      failedRows.forEach((i, detail) => _importSession.markFailed(i, detail));
      // Files the service never reached (the batch stopped on a failure OR a
      // requested cancel) are still Queued or Encrypting. A row left in either
      // state would keep isWorking true forever and the card would never
      // clear. A cancel is not a failure: its unreached rows read 'Cancelled'.
      final wasCancelled = _importSession.cancelRequested;
      for (var i = 0; i < _importSession.total; i++) {
        final status = _importSession.files[i].status;
        if (status == ImportFileStatus.queued ||
            status == ImportFileStatus.encrypting) {
          if (wasCancelled) {
            _importSession.markCancelled(i);
          } else {
            _importSession.markFailed(i, 'Not imported');
          }
        }
      }
      if (wasCancelled && mounted) {
        // Unimported originals untouched + already-saved originals kept: the
        // cancel skipped the batch-delete phase entirely, so the gallery is
        // exactly as it was before for every file not imported.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Import cancelled — ${result.successfulIds.length} of ${result.totalAttempted} imported. Unimported originals are still in the gallery.')));
      }
      if (result.successfulIds.isNotEmpty) {
        await _loadPhotos();
      }
      if (result.stoppedEarly && mounted) {
        final msg = _formatImportError(
          result.successfulIds.length,
          result.totalAttempted,
          result.failedFileName,
          result.error,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      // Let the outcome rows linger so the user sees them, then clear. The
      // timer is cancellable: dispose() stops it, and a new import cancels it
      // so a stale timer can never wipe the next session's rows mid-flight.
      if (mounted && _importSession.isActive && !_importSession.isWorking) {
        _lingerTimer?.cancel();
        _lingerTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && !_importSession.isWorking) _importSession.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = _formatImportError(0, 0, null, e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        _importSession.clear();
      }
    } finally {
      if (sessionActive && mounted) _importSession.clear();
      AutoLock().endProtectedOperation();
    }
  }

  String _formatImportError(
    int succeeded,
    int total,
    String? failedFileName,
    Object? error,
  ) {
    final String reason;
    final errStr = error?.toString() ?? '';
    final isLocked = errStr.contains('Vault is locked') || errStr.contains('locked');
    final isDamaged = error is CorruptedMediaFileException || errStr.contains('damaged') || errStr.contains('corrupted');

    final name = (failedFileName != null && failedFileName.isNotEmpty)
        ? '"$failedFileName"'
        : 'a photo';

    if (isLocked) {
      reason = 'the vault locked';
    } else if (isDamaged) {
      reason = '$name is damaged or unsupported';
    } else {
      reason = 'could not import $name';
    }

    if (succeeded > 0) {
      final remaining = total - succeeded;
      return 'Imported $succeeded of $total photos. Stopped because $reason ($remaining remaining not imported).';
    } else {
      if (isLocked) {
        return 'Could not import photos: the vault is locked.';
      } else if (isDamaged) {
        return 'Failed to import photos: $name is damaged or unsupported.';
      } else {
        return 'Failed to import photos: could not read $name.';
      }
    }
  }

  Future<void> _captureFromCamera() async {
    final id = await ref.read(fileVaultServiceProvider).captureAndEncryptImage();
    if (id != null) await _loadPhotos();
  }

  Future<void> _showOptions(PhotoMeta photo) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.unarchive, color: VaultColors.accent),
                ),
                title: const Text('Restore to Gallery', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _restorePhoto(photo);
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.drive_file_move_outlined, color: VaultColors.accent),
                ),
                title: const Text('Move to Folder', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showMoveToFolder(photo);
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: VaultColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete, color: VaultColors.error),
                ),
                title: const Text('Delete Permanently', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: VaultColors.error)),
                onTap: () {
                  Navigator.of(context).pop();
                  _deletePhoto(photo);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restorePhoto(PhotoMeta photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restore to Gallery',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'This decrypts the photo and writes it back into the device gallery, where other apps with media access can see it. After the gallery confirms the save, the encrypted vault copy is removed.',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _runRestore([photo]);
    }
  }

  /// Runs one or many photo restores through the restore activity session —
  /// the same pill + sheet model the video vault uses, so a batch restore is
  /// visible on the pill and stoppable. Cancellation stops the loop BEFORE
  /// the next photo, and the in-flight photo is checked again after its
  /// decrypt so a cancel still stops it before the gallery write; the vault
  /// copy is only removed after the gallery confirms the save, so a cancel
  /// can never lose a photo.
  Future<void> _runRestore(List<PhotoMeta> photos) async {
    final service = ref.read(fileVaultServiceProvider);
    _restoreLingerTimer?.cancel();
    _restoreSession
        .beginRestore(photos.map((p) => p.originalName ?? 'photo').toList());
    var restored = 0;
    var failed = 0;
    for (var i = 0; i < photos.length; i++) {
      if (_restoreSession.cancelRequested) break;
      final photo = photos[i];
      _restoreSession.markRestoring(i, i + 1);
      try {
        await service.restorePhotoToGallery(
          photo.id,
          isCancelled: () => _restoreSession.cancelRequested,
        );
        _restoreSession.markSaved(i);
        restored++;
      } on OperationCancelledException {
        // Cancelled before the photo reached the gallery: nothing changed,
        // so the row reads 'Cancelled' rather than pretending a failure.
        // Also mark the batch cancelled, so the loop stops after this photo
        // and the snackbar reports the truth instead of a bare count.
        _restoreSession.requestCancel();
        _restoreSession.markCancelled(i);
      } catch (e) {
        _restoreSession.markFailed(
            i, e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
        failed++;
      }
    }
    // Rows the cancelled loop never reached are still 'restoring'; they are
    // done now, and 'Cancelled' is their truth. Without this the session
    // would never settle and the pill would never clear.
    for (var i = 0; i < _restoreSession.total; i++) {
      if (_restoreSession.files[i].status == ImportFileStatus.restoring) {
        _restoreSession.markCancelled(i);
      }
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_restoreSession.cancelRequested
            ? 'Restore cancelled — $restored restored, the rest are still in the vault.'
            : failed == 0
                ? 'Restored $restored photo(s) to the gallery.'
                : 'Restored $restored of ${photos.length}; $failed failed (their vault copies were kept).')));
    // Let the outcome rows linger ~4s (same rule as the import card), then
    // clear so the pill disappears. A new restore cancels this timer first.
    if (_restoreSession.isActive && !_restoreSession.isWorking) {
      _restoreLingerTimer = Timer(const Duration(seconds: 4), () {
        if (!_restoreSession.isWorking) _restoreSession.clear();
      });
    }
    await _loadPhotos();
  }

  Future<void> _deletePhoto(PhotoMeta photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this photo?',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: VaultColors.error, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(fileVaultServiceProvider).deletePhoto(photo.id);
      HapticFeedback.mediumImpact();
      await _loadPhotos();
    }
  }

  /// Folder feature: visible-list filter + chips + move dialog.
  /// Mirrors DocumentVaultScreen; filter-only, blobs never move.
  List<PhotoMeta> _visiblePhotos() {
    if (_selectedFolder == null) return _photos;
    return _photos.where((p) => p.folder == _selectedFolder).toList();
  }

  Widget _folderChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              color: selected ? Colors.white : VaultColors.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: VaultColors.surface,
      selectedColor: VaultColors.accent,
      showCheckmark: false,
    );
  }

  Widget _buildFolderChips() {
    final folders = _photos
        .map((p) => p.folder)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final hasUnfiled = _photos.any((p) => p.folder.isEmpty);
    final chips = <Widget>[
      _folderChip('All', _selectedFolder == null,
          () => setState(() => _selectedFolder = null)),
    ];
    if (hasUnfiled) {
      chips.add(_folderChip('Unfiled', _selectedFolder == '',
          () => setState(() => _selectedFolder = '')));
    }
    for (final f in folders) {
      chips.add(_folderChip(f, _selectedFolder == f,
          () => setState(() => _selectedFolder = f)));
    }
    if (chips.length == 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips
            .map((c) => Padding(
                padding: const EdgeInsets.only(right: 8), child: c))
            .toList(),
      ),
    );
  }

  /// Shared folder picker. Every label carries an EXPLICIT dark color: the
  /// dialog background is white, but ListTile/TextField text otherwise
  /// inherits the app's dark-theme font (white), turning invisible.
  Future<String?> _pickFolder() async {
    final existingFolders = _photos
        .map((p) => p.folder)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final newFolderController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Move to folder',
            style: TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined,
                      color: VaultColors.textSecondary),
                  title: const Text('Unfiled',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: VaultColors.textPrimary)),
                  onTap: () => Navigator.of(context).pop(''),
                ),
                ...existingFolders.map((f) => ListTile(
                      leading: const Icon(Icons.folder_outlined,
                          color: VaultColors.accent),
                      title: Text(f,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              color: VaultColors.textPrimary)),
                      onTap: () => Navigator.of(context).pop(f),
                    )),
                const Divider(),
                TextField(
                  controller: newFolderController,
                  decoration: const InputDecoration(
                      hintText: 'New folder name',
                      hintStyle: TextStyle(fontFamily: 'Inter')),
                  style: const TextStyle(
                      fontFamily: 'Inter', color: VaultColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel',
                style: TextStyle(color: VaultColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              final name = newFolderController.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('Create & Move',
                style: TextStyle(color: VaultColors.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveToFolder(PhotoMeta photo) async {
    final chosen = await _pickFolder();
    if (chosen != null && mounted) {
      await ref.read(fileVaultServiceProvider).movePhoto(photo.id, chosen);
      await _loadPhotos();
    }
  }

  // ── Multi-select batch operations ────────────────────────────────────
  Future<void> _moveSelection() async {
    final chosen = await _pickFolder();
    if (chosen == null || !mounted) return;
    final service = ref.read(fileVaultServiceProvider);
    final ids = Set<String>.from(_selection);
    for (final id in ids) {
      await service.movePhoto(id, chosen);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Moved ${ids.length} photo(s) to '
            '${chosen.isEmpty ? 'Unfiled' : chosen}')));
    _clearSelection();
    await _loadPhotos();
  }

  Future<void> _deleteSelection() async {
    final count = _selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count photo(s)?',
            style: const TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter')),
        content: const Text(
            'This permanently removes the selected photos from the vault.',
            style: TextStyle(
                color: VaultColors.textSecondary, fontFamily: 'Inter')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: VaultColors.textTertiary, fontFamily: 'Inter'))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: VaultColors.error, fontFamily: 'Inter'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = ref.read(fileVaultServiceProvider);
    for (final id in Set<String>.from(_selection)) {
      await service.deletePhoto(id);
    }
    HapticFeedback.mediumImpact();
    _clearSelection();
    await _loadPhotos();
  }

  /// Moves the selected photos back OUT of the vault into the device gallery.
  /// The mirror of bulk import: every photo is decrypted, written to the
  /// gallery and — only after the gallery confirms — removed from the vault.
  /// A photo whose restore fails keeps its encrypted copy; the snackbar
  /// reports both truths instead of a single optimistic number.
  Future<void> _restoreSelection() async {
    final count = _selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Restore $count photo(s) to the gallery?',
            style: const TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter')),
        content: const Text(
            'This decrypts the selected photos and writes them back into the device gallery, where other apps with media access can see them. After each save is confirmed, the vault copy is removed.',
            style: TextStyle(
                color: VaultColors.textSecondary, fontFamily: 'Inter')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: VaultColors.textTertiary,
                      fontFamily: 'Inter'))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore',
                  style: TextStyle(
                      color: VaultColors.accent, fontFamily: 'Inter'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Collect from the CURRENT selection before clearing, then hand the whole
    // batch to the restore session (pill + sheet + cancel), like the video
    // vault's bulk restore.
    final chosen =
        _visiblePhotos().where((p) => _selection.contains(p.id)).toList();
    _clearSelection();
    await _runRestore(chosen);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selection.remove(id)) _selection.add(id);
    });
  }

  void _clearSelection() => setState(_selection.clear);

  void _openViewer(int initialIndex) {
    // Folder feature: the viewer pages through the FILTERED list the grid
    // shows, so pass the visible list and map its index back to _photos for
    // delete (delete removes by id, so the filter is unaffected).
    final visible = _visiblePhotos();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoViewerScreen(
          photos: visible,
          initialIndex: initialIndex,
          loadBytes: _loadPhotoBytes,
          onDelete: (id) async {
            await ref.read(fileVaultServiceProvider).deletePhoto(id);
            await _loadPhotos();
          },
          onRestore: (id) async {
            // Captured BEFORE the await: a closure's context use after an
            // async gap is not covered by the State's mounted check in the
            // linter's eyes (use_build_context_synchronously), and grabbing
            // the messenger synchronously removes the cross-gap use entirely.
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ref
                  .read(fileVaultServiceProvider)
                  .restorePhotoToGallery(id);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Photo restored to gallery successfully.')));
              }
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(SnackBar(
                    content: Text(e
                        .toString()
                        .replaceFirst(RegExp(r'^Exception:\s*'), ''))));
              }
            }
            await _loadPhotos();
          },
        ),
      ),
    );
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: VaultColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _importFromGallery();
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: VaultColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Take a Photo', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _captureFromCamera();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crypto = ref.watch(vaultCryptoProvider);
    if (!crypto.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route == null || !route.isCurrent) return;
        Navigator.of(context).pushReplacementNamed('/vault-pin');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return VaultScaffold(
      title: 'Photos',
      actions: _selection.isNotEmpty
          ? [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Clear selection',
                onPressed: _clearSelection,
              ),
            ]
          : null,
      floatingActionButton: _selection.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: VaultColors.accent,
              onPressed: null, // visual only; real actions live in the bar below
              label: Text('${_selection.length} selected',
                  style: const TextStyle(color: Colors.white)),
            )
          : Column(
              // Import status pill + the + FAB form one cluster bottom-right
              // (mirrors VideoVaultScreen; replaces the old above-grid card).
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ImportActivityButton(
                  key: const ValueKey('restore_activity_button'),
                  session: _restoreSession,
                  onTap: () => showImportDetailsSheet(context, _restoreSession),
                ),
                const SizedBox(height: 12),
                ImportActivityButton(
                  key: const ValueKey('import_activity_button'),
                  session: _importSession,
                  onTap: () => showImportDetailsSheet(context, _importSession),
                ),
                const SizedBox(height: 12),
                AnimatedFAB(
                  child: FloatingActionButton(
                    onPressed: _showImportOptions,
                    backgroundColor: VaultColors.accent,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _photos.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_outlined,
                              size: 80,
                              color: VaultColors.accent.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No photos yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: VaultColors.textTertiary,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap + to import your first photo',
                              style: TextStyle(
                                fontSize: 14,
                                color: VaultColors.textTertiary.withValues(alpha: 0.7),
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildFolderChips(),
                    if (_selection.isNotEmpty)
                      Material(
                        color: VaultColors.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Text('${_selection.length} selected',
                                  style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: VaultColors.textSecondary)),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _moveSelection,
                                icon: const Icon(Icons.drive_file_move_outlined,
                                    size: 20, color: VaultColors.accent),
                                label: const Text('Move',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: VaultColors.accent)),
                              ),
                              TextButton.icon(
                                onPressed: _restoreSelection,
                                icon: const Icon(Icons.unarchive,
                                    size: 20, color: VaultColors.accent),
                                label: const Text('Restore',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: VaultColors.accent)),
                              ),
                              TextButton.icon(
                                onPressed: _deleteSelection,
                                icon: const Icon(Icons.delete,
                                    size: 20, color: VaultColors.error),
                                label: const Text('Delete',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: VaultColors.error)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: _visiblePhotos().isEmpty
                          ? const Center(
                              child: Text(
                                'No photos in this folder',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: VaultColors.textTertiary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(2),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              itemCount: _visiblePhotos().length,
                              itemBuilder: (context, index) {
                                final photo = _visiblePhotos()[index];
                                final thumbPx = (MediaQuery.of(context).size.width / 3 * MediaQuery.of(context).devicePixelRatio).round().clamp(150, 600);
                                final selected = _selection.contains(photo.id);
                                return GestureDetector(
                                  onTap: () {
                                    if (_selection.isNotEmpty) {
                                      _toggleSelection(photo.id);
                                    } else {
                                      _openViewer(index);
                                    }
                                  },
                                  onLongPress: () {
                                    if (_selection.isEmpty) {
                                      _toggleSelection(photo.id);
                                    } else {
                                      _showOptions(photo);
                                    }
                                  },
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _PhotoThumbnail(
                                        key: ValueKey(photo.id),
                                        photoId: photo.id,
                                        thumbPx: thumbPx,
                                        loadBytes: _loadPhotoBytes,
                                      ),
                                      if (selected)
                                        Container(
                                          color: VaultColors.accent
                                              .withValues(alpha: 0.35),
                                        ),
                                      // No badge circle: selected state is
                                      // the tint above (photos) / border +
                                      // tint (videos). Long-press enters
                                      // selection; tap toggles.
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _PhotoThumbnail extends StatefulWidget {
  final String photoId;
  final int thumbPx;
  final Future<Uint8List?> Function(String) loadBytes;

  const _PhotoThumbnail({
    super.key,
    required this.photoId,
    required this.thumbPx,
    required this.loadBytes,
  });

  @override
  State<_PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<_PhotoThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final b = await widget.loadBytes(widget.photoId);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _failed = b == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    if (_bytes == null) {
      return Container(
        color: Colors.grey[200],
      );
    }
    return Image.memory(
      _bytes!,
      cacheWidth: widget.thumbPx,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}
