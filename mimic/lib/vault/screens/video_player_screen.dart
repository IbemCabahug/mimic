// lib/vault/screens/video_player_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../security/vault_error_ui.dart';
import '../crypto/vault_crypto.dart';
import '../services/media_stream_server.dart';
import '../security/auto_lock.dart';

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
  bool _disposed = false;

  @override
  void initState() {
    AutoLock().suspend();
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final url = await MediaStreamServer.instance.urlFor(widget.videoId);
      if (!mounted || _disposed) return;
      final controller = VideoPlayerController.networkUrl(url);
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
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
    _chewieController?.dispose();
    _videoPlayerController?.pause();
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
          ? const Center(
              child: Text(
                'Error playing video.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            )
          : _chewieController != null
              ? SafeArea(
                  child: Chewie(
                    controller: _chewieController!,
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Color(0xFF7F77DD)),
                ),
    );
  }
}
