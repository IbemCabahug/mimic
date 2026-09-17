// lib/vault/screens/video_player_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../security/vault_error_ui.dart';
import '../crypto/vault_crypto.dart';
import '../services/media_stream_server.dart';
import '../security/auto_lock.dart';
import 'player_failure_text.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;

  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;
  String? _errorMessage;
  bool _disposed = false;
  VoidCallback? _chewieFullscreenListener;
  bool _wasFullscreen = false;

  @override
  void initState() {
    AutoLock().suspend();
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // H16/F4: the conversion's typed fate must reach this screen instead of
      // looking like an endless spinner. streamableUrlFor is the only caller
      // of ensureVideoStreamable, so this is where the outcome arrives.
      final (url, outcome) =
          await MediaStreamServer.instance.streamableUrlFor(widget.videoId);
      if (!mounted || _disposed) return;
      // Log-only by the path-free rule (video_vault_service.dart:407-415): the
      // detail can carry a path fragment and is never rendered.
      if (outcome.detail != null) {
        debugPrint('video ${widget.videoId} conversion: ${outcome.detail}');
      }
      final controller = VideoPlayerController.networkUrl(url);
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      // A refused or aborted conversion becomes plain words, not a spinner
      // that never ends. A player that DID initialize plays on purpose:
      // playerReady swallows even a failure outcome (test U6), because an
      // already-c2 blob can be servable while the outcome still says io.
      final failure = playerFailureFor(
        outcome,
        playerReady: controller.value.isInitialized,
      );
      if (failure != PlayerOpenFailure.none) {
        await controller.dispose();
        setState(() {
          _hasError = true;
          _errorMessage = playerFailureMessage(failure, outcome.detail);
        });
        return;
      }
      // Fullscreen rebuild robustness: the video aspect ratio is snapshotted
      // from the initialized player and pinned on the Chewie controller, so
      // the fullscreen route (a new route + relayout on a larger surface)
      // reuses the same sizing instead of re-measuring mid-rotation. The
      // controller is created ONCE per play — _initializePlayer never runs
      // again for a fullscreen toggle — and the listener below only calls
      // setState on the isFullScreen EDGE, so continuous playback frames
      // never rebuild this widget.
      final size = controller.value.size;
      final double aspect = (size.width > 0 && size.height > 0)
          ? size.width / size.height
          : 16 / 9;
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: aspect,
        allowFullScreen: true,
        fullScreenByDefault: false,
        deviceOrientationsOnEnterFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF7F77DD),
          handleColor: const Color(0xFF7F77DD),
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
        placeholder: const Center(
          child: CircularProgressIndicator(color: Color(0xFF7F77DD)),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      if (!mounted || _disposed) {
        chewie.dispose();
        await controller.dispose();
        return;
      }
      _wasFullscreen = chewie.isFullScreen;
      _chewieFullscreenListener = () {
        if (_disposed || !mounted) return;
        final now = chewie.isFullScreen;
        if (now == _wasFullscreen) return;
        _wasFullscreen = now;
        // Rebuild once per edge so the inline/fullscreen chrome swaps.
        setState(() {});
      };
      chewie.addListener(_chewieFullscreenListener!);
      setState(() {
        _videoPlayerController = controller;
        _chewieController = chewie;
      });
    } on SystemKeyMissingException catch (_) {
      if (!mounted || _disposed) return;
      showSecureKeyLostSnackBar(context);
      setState(() {
        _hasError = true;
      });
    } catch (e) {
      debugPrint('Failed to initialize video player: $e');
      if (!mounted || _disposed) return;
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    AutoLock().resume();
    _disposed = true;
    // L22 (device 2026-09-15: audio 1-2 s after Back): pause FIRST so no
    // audio frame is emitted after the route is popped, then release the
    // Chewie wrapper before the player it drives, then stop the media
    // server. dispose() is synchronous, so the order is the fix — there is
    // nothing to await.
    _videoPlayerController?.pause();
    final fullscreenListener = _chewieFullscreenListener;
    if (fullscreenListener != null) {
      try {
        _chewieController?.removeListener(fullscreenListener);
      } catch (_) {}
      _chewieFullscreenListener = null;
    }
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    unawaited(MediaStreamServer.instance.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _errorMessage ?? 'Error playing video.',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _chewieController != null
              ? SafeArea(
                  child: Chewie(
                    controller: _chewieController!,
                  ),
                )
              // F4: a first play that is converting must say so. The text is
              // static on purpose — there is no progress API to poll, and the
              // 3G-0 baseline proved the wait ends (H8), so no spinner-only
              // dead air and no fake percentage.
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF7F77DD)),
                      SizedBox(height: 16),
                      Text(
                        'Preparing video… first plays convert it to a seekable format, which can take a while for long videos.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
    );
  }
}
