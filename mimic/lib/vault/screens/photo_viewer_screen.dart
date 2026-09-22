// lib/vault/screens/photo_viewer_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_vault_service.dart';

class PhotoViewerScreen extends ConsumerStatefulWidget {
  final List<PhotoMeta> photos;
  final int initialIndex;
  final Future<Uint8List?> Function(String) loadBytes;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onRestore;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.loadBytes,
    required this.onDelete,
    required this.onRestore,
  });

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _isZoomed = false;

  /// F8: one cached load future per photo id.
  ///
  /// The future used to be created inside itemBuilder, so it was rebuilt on
  /// every parent setState. A double-tap zoom calls onZoomChanged, which calls
  /// setState on this screen, which handed FutureBuilder a *new* future — the
  /// builder dropped to ConnectionState.waiting, tore _ZoomablePhoto down and
  /// threw away its TransformationController. The photo visibly bounced back
  /// to scale 1.0, so the first double-tap looked like it did nothing and only
  /// the second one stuck (the second finds _isZoomed already true, so no
  /// rebuild happens). Caching the future keeps the widget alive across
  /// rebuilds and the zoom now engages on the first tap.
  final Map<String, Future<Uint8List?>> _bytesFutures = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant PhotoViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A delete or restore changes the list. Drop the entries that are gone so
    // a removed photo's bytes are not held for the rest of the session, and so
    // a photo re-added later reloads instead of replaying a stale result.
    if (!identical(oldWidget.photos, widget.photos)) {
      final liveIds = widget.photos.map((p) => p.id).toSet();
      _bytesFutures.removeWhere((id, _) => !liveIds.contains(id));
    }
  }

  /// Returns the cached future for [photo], starting the decrypt on first use.
  ///
  /// A failed load is deliberately NOT cached: the broken-image placeholder
  /// must be retryable by leaving and returning, rather than becoming
  /// permanent for the rest of the session.
  Future<Uint8List?> _bytesFor(PhotoMeta photo) {
    return _bytesFutures.putIfAbsent(photo.id, () {
      final future = widget.loadBytes(photo.id);
      unawaited(
        future.then((bytes) {
          if (bytes == null) _bytesFutures.remove(photo.id);
        }).catchError((Object _) {
          _bytesFutures.remove(photo.id);
          return null;
        }),
      );
      return future;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Restores the photo being viewed back to the device gallery, with the
  /// same honest warning the grid's sheet shows. The actual vault write and
  /// vault delete live in the service; the grid owns the snackbar and the
  /// list refresh through the onRestore callback.
  Future<void> _restoreCurrent() async {
    if (widget.photos.isEmpty) return;
    final photo = widget.photos[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restore to Gallery',
          style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'This decrypts the photo and writes it back into the device gallery, where other apps with media access can see it. After the gallery confirms the save, the encrypted vault copy is removed.',
          style: TextStyle(color: Color(0xFF6B6B6B), fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E8E), fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.onRestore(photo.id);
      if (mounted && widget.photos.length <= 1) {
        Navigator.of(context).pop();
      }
    }
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
            icon: const Icon(Icons.unarchive, color: Colors.white),
            tooltip: 'Restore to gallery',
            onPressed: _restoreCurrent,
          ),
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
                  future: _bytesFor(photo),
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
