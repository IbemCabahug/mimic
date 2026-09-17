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
    _bytesCache.clear();
    _bytesCacheSize = 0;
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
    try {
      final result = await ref.read(fileVaultServiceProvider).pickAndEncryptImage(context);
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
    } catch (e) {
      if (mounted) {
        final msg = _formatImportError(0, 0, null, e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
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
          'Move this photo back to the device gallery? It will be removed from the vault.',
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
        await ref.read(fileVaultServiceProvider).restorePhotoToGallery(photo.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo restored to gallery successfully.')),
          );
          await _loadPhotos();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to restore photo: $e')),
          );
        }
      }
    }
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

  Future<void> _showMoveToFolder(PhotoMeta photo) async {
    final existingFolders = _photos
        .map((p) => p.folder)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final newFolderController = TextEditingController();
    final chosen = await showDialog<String>(
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
                      style: TextStyle(fontFamily: 'Inter')),
                  onTap: () => Navigator.of(context).pop(''),
                ),
                ...existingFolders.map((f) => ListTile(
                      leading: const Icon(Icons.folder_outlined,
                          color: VaultColors.accent),
                      title:
                          Text(f, style: const TextStyle(fontFamily: 'Inter')),
                      onTap: () => Navigator.of(context).pop(f),
                    )),
                const Divider(),
                TextField(
                  controller: newFolderController,
                  decoration: const InputDecoration(
                      hintText: 'New folder name',
                      hintStyle: TextStyle(fontFamily: 'Inter')),
                  style: const TextStyle(fontFamily: 'Inter'),
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
    if (chosen != null && mounted) {
      await ref.read(fileVaultServiceProvider).movePhoto(photo.id, chosen);
      await _loadPhotos();
    }
  }

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
      floatingActionButton: AnimatedFAB(
        child: FloatingActionButton(
          onPressed: _showImportOptions,
          backgroundColor: VaultColors.accent,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _photos.isEmpty
              ? Center(
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
                )
              : Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildFolderChips(),
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
                                return GestureDetector(
                                  onTap: () => _openViewer(index),
                                  onLongPress: () => _showOptions(photo),
                                  child: _PhotoThumbnail(
                                    key: ValueKey(photo.id),
                                    photoId: photo.id,
                                    thumbPx: thumbPx,
                                    loadBytes: _loadPhotoBytes,
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
