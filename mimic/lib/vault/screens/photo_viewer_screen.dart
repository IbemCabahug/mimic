// lib/vault/screens/photo_viewer_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_vault_service.dart';

class PhotoViewerScreen extends ConsumerStatefulWidget {
  final List<PhotoMeta> photos;
  final int initialIndex;
  final ValueChanged<String> onDelete;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deleteCurrent() async {
    if (widget.photos.isEmpty) return;
    final photo = widget.photos[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'Delete this photo permanently?',
          style: TextStyle(color: Color(0xFF6B6B6B), fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E8E), fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.onDelete(photo.id);
      if (mounted && widget.photos.length <= 1) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _deleteCurrent,
          ),
        ],
      ),
      body: widget.photos.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemCount: widget.photos.length,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return FutureBuilder<Uint8List?>(
                  future: ref.read(fileVaultServiceProvider).getPhoto(photo.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const Center(child: Icon(Icons.broken_image, color: Colors.white));
                    }
                    return Center(
                      child: InteractiveViewer(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
