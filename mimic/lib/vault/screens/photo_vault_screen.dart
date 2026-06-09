import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPhotos();
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
    final id = await ref.read(fileVaultServiceProvider).pickAndEncryptImage();
    if (id != null) await _loadPhotos();
  }

  Future<void> _captureFromCamera() async {
    final id = await ref.read(fileVaultServiceProvider).captureAndEncryptImage();
    if (id != null) await _loadPhotos();
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

  void _openViewer(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoViewerScreen(
          photos: _photos,
          initialIndex: initialIndex,
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
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return FutureBuilder<Uint8List?>(
                      future: ref.read(fileVaultServiceProvider).getPhoto(photo.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.white,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: VaultColors.accent),
                              ),
                            ),
                          );
                        }

                        final bytes = snapshot.data;
                        if (bytes == null) {
                          return Container(
                            color: Colors.white,
                            child: const Icon(Icons.broken_image, color: VaultColors.textTertiary),
                          );
                        }

                        return GestureDetector(
                          onTap: () => _openViewer(index),
                          onLongPress: () => _deletePhoto(photo),
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            cacheWidth: 300,
                            cacheHeight: 300,
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
