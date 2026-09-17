// lib/vault/screens/video_vault_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/video_thumbnail_service.dart';
import '../services/video_vault_service.dart';
import '../security/auto_lock.dart';
import '../crypto/vault_crypto.dart';
import '../widgets/vault_scaffold.dart';
import '../widgets/import_activity_button.dart';
import '../services/import_progress.dart';
import '../../core/theme/app_theme.dart';
import 'video_player_screen.dart';

class VideoVaultScreen extends ConsumerStatefulWidget {
  const VideoVaultScreen({super.key});

  @override
  ConsumerState<VideoVaultScreen> createState() => _VideoVaultScreenState();
}

class _VideoVaultScreenState extends ConsumerState<VideoVaultScreen> {
  List<VideoMeta> _videos = [];
  bool _isLoading = true;
  // Folder feature (mirrors DocumentVaultScreen): null = All, '' = Unfiled,
  // otherwise the folder name. Filter-only.
  String? _selectedFolder;
  // Multi-select: video ids currently ticked. Empty set = selection mode off.
  final Set<String> _selection = {};
  // Live import card: one session per picker return; the card above the grid
  // shows Queued -> Encrypting N/M -> delete-confirm wait -> Saved, so a 2:34
  // video no longer looks dead while it encrypts.
  final ImportSession _importSession = ImportSession();
  // Keeps a settled card on screen ~4s so the outcome is seen, then clears it.
  // Cancellable: dispose() cancels it (no pending timer after the screen is
  // gone) and the next import cancels it, so a stale timer can never wipe the
  // new session's rows.
  Timer? _lingerTimer;

  @override
  void dispose() {
    _lingerTimer?.cancel();
    _importSession.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // F23-FIX: lock is the cache's kill switch, enforced at both ends.
    // (a) Wipe on entry: a re-opened vault always starts frameless and
    // regenerates progressively, no matter which path locked it (lock button,
    // auto-lock, conceal — several dispose this screen, so a listener
    // registered here can never be relied on to observe the transition;
    // that is exactly the reported "thumbnail still there after re-open"
    // bug). (b) The pre-existing listener below covers the still-mounted
    // case (auto-lock firing while the grid is visible).
    //
    // ignore: discarded_futures — fire-and-forget is intended; the grid
    // rebuilds progressively as frames land via videoThumbnailCacheProvider.
    ref.read(videoThumbnailCacheProvider.notifier).wipe();
    _loadVideos();
    ref.listenManual(vaultCryptoProvider, (VaultCrypto? prev, VaultCrypto next) {
      if (prev != null && prev.isUnlocked && !next.isUnlocked) {
        if (mounted) {
          ref.read(videoThumbnailCacheProvider.notifier).wipe();
          setState(() {});
        }
      }
    });
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await ref.read(videoVaultServiceProvider).getAllVideos();
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
    // F23: queue thumbnails in list order; a tile that scrolls into view later
    // re-requests itself with priority inside the item builder.
    final thumbnails = ref.read(videoThumbnailServiceProvider);
    for (final video in videos) {
      thumbnails.request(video.id);
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
      final result = await ref.read(videoVaultServiceProvider).pickAndEncryptVideo(
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
      );
      sessionActive = false;
      // Outcome rows: per-file Saved / Saved-original-kept. The snackbar
      // verdicts below stay as the second signal; the card is the first.
      // originalsKept == true means the source was left on the device (dialog
      // denied, platform refusal, or the delete phase never ran).
      for (final i in savedRows) {
        if (result.originalsKept) {
          _importSession.markSavedOriginalKept(i);
        } else {
          _importSession.markSaved(i);
        }
      }
      failedRows.forEach((i, detail) => _importSession.markFailed(i, detail));
      // Files the service never reached (the batch stopped on a failure) are
      // still Queued or Encrypting. A row left in either state would keep
      // isWorking true forever and the card would never clear.
      for (var i = 0; i < _importSession.total; i++) {
        final status = _importSession.files[i].status;
        if (status == ImportFileStatus.queued ||
            status == ImportFileStatus.encrypting) {
          _importSession.markFailed(i, 'Not imported');
        }
      }
      if (result.successfulIds.isNotEmpty) {
        await _loadVideos();
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
        : 'a video';

    if (isLocked) {
      reason = 'the vault locked';
    } else if (isDamaged) {
      reason = '$name is damaged or unsupported';
    } else {
      reason = 'could not import $name';
    }

    if (succeeded > 0) {
      final remaining = total - succeeded;
      return 'Imported $succeeded of $total videos. Stopped because $reason ($remaining remaining not imported).';
    } else {
      if (isLocked) {
        return 'Could not import videos: the vault is locked.';
      } else if (isDamaged) {
        return 'Failed to import videos: $name is damaged or unsupported.';
      } else {
        return 'Failed to import videos: could not read $name.';
      }
    }
  }

  Future<void> _showOptions(VideoMeta video) async {
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
                  _restoreVideo(video);
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
                  _showMoveToFolder(video);
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
                  _deleteVideo(video);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreVideo(VideoMeta video) async {
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
          'Move this video back to the device gallery? It will be removed from the vault.',
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
      try {
        await ref.read(videoVaultServiceProvider).restoreVideoToGallery(video.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video restored to gallery successfully.')),
          );
          await _loadVideos();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to restore video: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteVideo(VideoMeta video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Video',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this video?',
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
      await ref.read(videoVaultServiceProvider).deleteVideo(video.id);
      HapticFeedback.mediumImpact();
      await _loadVideos();
    }
  }

  /// Folder feature: folder chips (All / Unfiled / names) + move-to-folder
  /// dialog. Mirrors DocumentVaultScreen; filter-only, blobs never move.
  List<VideoMeta> _visibleVideos() {
    if (_selectedFolder == null) return _videos;
    return _videos.where((v) => v.folder == _selectedFolder).toList();
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
    final folders = _videos
        .map((v) => v.folder)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final hasUnfiled = _videos.any((v) => v.folder.isEmpty);
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
    final existingFolders = _videos
        .map((v) => v.folder)
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

  Future<void> _showMoveToFolder(VideoMeta video) async {
    final chosen = await _pickFolder();
    if (chosen != null && mounted) {
      await ref.read(videoVaultServiceProvider).moveVideo(video.id, chosen);
      await _loadVideos();
    }
  }

  // ── Multi-select batch operations ────────────────────────────────────
  Future<void> _moveSelection() async {
    final chosen = await _pickFolder();
    if (chosen == null || !mounted) return;
    final service = ref.read(videoVaultServiceProvider);
    final ids = Set<String>.from(_selection);
    for (final id in ids) {
      await service.moveVideo(id, chosen);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Moved ${ids.length} video(s) to '
            '${chosen.isEmpty ? 'Unfiled' : chosen}')));
    _clearSelection();
    await _loadVideos();
  }

  Future<void> _deleteSelection() async {
    final count = _selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count video(s)?',
            style: const TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter')),
        content: const Text(
            'This permanently removes the selected videos from the vault.',
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
    final service = ref.read(videoVaultServiceProvider);
    for (final id in Set<String>.from(_selection)) {
      await service.deleteVideo(id);
    }
    HapticFeedback.mediumImpact();
    _clearSelection();
    await _loadVideos();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selection.remove(id)) _selection.add(id);
    });
  }

  void _clearSelection() => setState(_selection.clear);

  Future<void> _playVideo(VideoMeta video) async {
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(videoId: video.id),
        ),
      );
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final crypto = ref.watch(vaultCryptoProvider);
    final thumbnails = ref.watch(videoThumbnailCacheProvider);
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
      title: 'Videos',
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
              onPressed: null,
              label: Text('${_selection.length} selected',
                  style: const TextStyle(color: Colors.white)),
            )
          : Column(
              // Import status pill + the + FAB form one cluster bottom-right.
              // UX note (2026-09-17): the pill replaces the old above-grid
              // status card — same truthful counts, no grid space stolen.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ImportActivityButton(
                  key: const ValueKey('import_activity_button'),
                  session: _importSession,
                  onTap: () => showImportDetailsSheet(context, _importSession),
                ),
                const SizedBox(height: 12),
                AnimatedFAB(
                  child: FloatingActionButton(
                    onPressed: _importFromGallery,
                    backgroundColor: VaultColors.accent,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _videos.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                        Icons.video_library_outlined,
                        size: 80,
                        color: VaultColors.accent.withValues(alpha: 0.2),
                      ),
                            const SizedBox(height: 16),
                            const Text(
                              'No videos yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: VaultColors.textTertiary,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap + to import your first video',
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
                      child: _visibleVideos().isEmpty
                          ? const Center(
                              child: Text(
                                'No videos in this folder',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: VaultColors.textTertiary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.2,
                              ),
                              itemCount: _visibleVideos().length,
                              itemBuilder: (context, index) {
                                final video = _visibleVideos()[index];
                                final frame = thumbnails[video.id];
                                final selected = _selection.contains(video.id);
                                if (frame == null) {
                                  // F23: this tile is visible but has no frame yet — jump
                                  // the queue so what the owner is looking at fills first.
                                  ref
                                      .read(videoThumbnailServiceProvider)
                                      .request(video.id, priority: true);
                                }
                                return GestureDetector(
                                  onTap: () {
                                    if (_selection.isNotEmpty) {
                                      _toggleSelection(video.id);
                                    } else {
                                      _playVideo(video);
                                    }
                                  },
                                  onLongPress: () {
                                    if (_selection.isEmpty) {
                                      _toggleSelection(video.id);
                                    } else {
                                      _showOptions(video);
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: VaultColors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: selected
                                              ? VaultColors.accent
                                              : VaultColors.textTertiary
                                                  .withValues(alpha: 0.1),
                                          width: selected ? 2 : 1),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (frame != null)
                                            Image.memory(
                                              frame,
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              errorBuilder: (_, _, _) =>
                                                  const Center(
                                                child: Icon(
                                                  Icons.play_circle_fill,
                                                  size: 50,
                                                  color: VaultColors.accent,
                                                ),
                                              ),
                                            )
                                          else
                                            const Center(
                                              child: Icon(
                                                Icons.play_circle_fill,
                                                size: 50,
                                                color: VaultColors.accent,
                                              ),
                                            ),
                                          if (selected)
                                            Positioned.fill(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: VaultColors.accent
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                            ),
                                          // No badge circle: selected state is the
                                          // accent border + the tint above.
                                          // Long-press enters selection; tap
                                          // toggles.
                                          if (frame != null)
                                            Positioned.fill(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    stops: const [0.45, 1.0],
                                                    colors: [
                                                      Colors.transparent,
                                                      Colors.black.withValues(alpha: 0.55),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            bottom: 8,
                                            left: 8,
                                            right: 8,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  video.originalName ??
                                                      'Video ${index + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        // F23-FIX: tile sits over a dark photo/frame with a
                                        // black scrim — dark VaultColors.textPrimary (#1A1A1A)
                                        // is unreadable there, so overlay text is white.
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(video.durationS),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 10,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                        Text(
                                          '${(video.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 10,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
