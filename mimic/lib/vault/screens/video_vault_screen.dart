// lib/vault/screens/video_vault_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/video_vault_service.dart';
import '../widgets/vault_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    _loadVideos();
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
  }

  Future<void> _importFromGallery() async {
    final ids = await ref.read(videoVaultServiceProvider).pickAndEncryptVideo(context);
    if (ids.isNotEmpty) await _loadVideos();
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

  Future<void> _playVideo(VideoMeta video) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: VaultColors.accent),
      ),
    );

    try {
      final bytes = await ref.read(videoVaultServiceProvider).getVideo(video.id);
      if (bytes == null) throw Exception('Video file bytes not found.');

      final tempDir = await getTemporaryDirectory();
      final originalName = video.originalName ?? '${video.id}.mp4';
      final tempFile = File(p.join(tempDir.path, 'temp_video_${video.id}_$originalName'));
      await tempFile.writeAsBytes(bytes);

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(tempFilePath: tempFile.path),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decrypt video: $e')),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Videos',
      floatingActionButton: AnimatedFAB(
        child: FloatingActionButton(
          onPressed: _importFromGallery,
          backgroundColor: VaultColors.accent,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _videos.isEmpty
              ? Center(
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
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return GestureDetector(
                      onTap: () => _playVideo(video),
                      onLongPress: () => _showOptions(video),
                      child: Container(
                        decoration: BoxDecoration(
                          color: VaultColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VaultColors.textTertiary.withValues(alpha: 0.1)),
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                size: 50,
                                color: VaultColors.accent,
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
                                    video.originalName ?? 'Video ${index + 1}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: VaultColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(video.durationS),
                                        style: const TextStyle(
                                          color: VaultColors.textSecondary,
                                          fontSize: 10,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      Text(
                                        '${(video.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                        style: const TextStyle(
                                          color: VaultColors.textSecondary,
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
                    );
                  },
                ),
    );
  }
}
