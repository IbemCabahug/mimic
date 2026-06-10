// lib/vault/screens/video_player_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String tempFilePath;

  const VideoPlayerScreen({super.key, required this.tempFilePath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.file(File(widget.tempFilePath));
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
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
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Failed to initialize video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController.dispose();
    try {
      final file = File(widget.tempFilePath);
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint('Temporary video file deleted: ${widget.tempFilePath}');
      }
    } catch (e) {
      debugPrint('Failed to delete temporary video file: $e');
    }
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
          : _chewieController != null &&
                  _chewieController!.videoPlayerController.value.isInitialized
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
