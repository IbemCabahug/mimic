// lib/vault/screens/photo_viewer_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_vault_service.dart';

class PhotoViewerScreen extends ConsumerStatefulWidget {
  final List<PhotoMeta> photos;
  final int initialIndex;
  final Future<Uint8List?> Function(String) loadBytes;
  final ValueChanged<String> onDelete;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.loadBytes,
    required this.onDelete,
  });

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _isZoomed = false;

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
              physics: _isZoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _isZoomed = false;
                });
              },
              itemCount: widget.photos.length,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return FutureBuilder<Uint8List?>(
                  future: widget.loadBytes(photo.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const Center(child: Icon(Icons.broken_image, color: Colors.white));
                    }
                    return _ZoomablePhoto(
                      key: ValueKey(photo.id),
                      bytes: bytes,
                      onZoomChanged: (z) {
                        if (z != _isZoomed) setState(() => _isZoomed = z);
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final Uint8List bytes;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    required super.key,
    required this.bytes,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
  }

  void _handleDoubleTapDown(TapDownDetails d) => _doubleTapDetails = d;

  void _handleDoubleTap() {
    final current = _controller.value.getMaxScaleOnAxis();
    Matrix4 target;
    if (current > 1.01) {
      target = Matrix4.identity();
    } else {
      final p = _doubleTapDetails!.localPosition;
      const s = 2.5;
      target = Matrix4.identity()
        ..translate(-p.dx * (s - 1), -p.dy * (s - 1))
        ..scale(s);
    }
    _animateTo(target);
  }

  void _animateTo(Matrix4 target) {
    _animation?.removeListener(_onAnimate);
    _animation = Matrix4Tween(begin: _controller.value, end: target)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animation!.addListener(_onAnimate);
    _animController.forward(from: 0);
  }

  void _onAnimate() => _controller.value = _animation!.value;

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _animation?.removeListener(_onAnimate);
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1.0,
        maxScale: 5.0,
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
