// lib/vault/screens/audio_recorder_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/audio_vault_service.dart';

class AudioRecorderScreen extends ConsumerStatefulWidget {
  const AudioRecorderScreen({super.key});

  @override
  ConsumerState<AudioRecorderScreen> createState() => _AudioRecorderScreenState();
}

class _AudioRecorderScreenState extends ConsumerState<AudioRecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  Duration _recordedDuration = Duration.zero;
  Timer? _timer;
  String? _tempPath;
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.text = 'Recording ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      _tempPath = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _tempPath!,
      );

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedDuration = Duration.zero;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordedDuration += const Duration(seconds: 1));
        }
      });
    }
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    setState(() => _isPaused = true);
    _timer?.cancel();
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    setState(() => _isPaused = false);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _recordedDuration += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _timer?.cancel();

    setState(() {
      _isRecording = false;
      _isPaused = false;
    });

    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final durationMs = _recordedDuration.inMilliseconds;
        final title = _titleController.text.trim().isEmpty
            ? 'Recording ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}'
            : _titleController.text.trim();

        await ref.read(audioVaultServiceProvider).saveAudio(
              bytes,
              'audio/m4a',
              title: title,
              durationMs: durationMs,
            );

        await file.delete();

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      _timer?.cancel();
    }
    if (_tempPath != null) {
      final file = File(_tempPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1EFE8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Record Audio',
          style: TextStyle(
            color: Color(0xFF534AB7),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF534AB7)),
          onPressed: _cancelRecording,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRecording) ...[
                Text(
                  _formatDuration(_recordedDuration),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isPaused ? 'Paused' : 'Recording...',
                  style: TextStyle(
                    fontSize: 16,
                    color: _isPaused
                        ? const Color(0xFFD85A30)
                        : Colors.redAccent,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isPaused)
                      ElevatedButton.icon(
                        onPressed: _resumeRecording,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: const Text('Resume', style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF534AB7),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _pauseRecording,
                        icon: const Icon(Icons.pause, color: Colors.white),
                        label: const Text('Pause', style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD85A30),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop, color: Colors.white),
                      label: const Text('Stop', style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _titleController,
                  style: const TextStyle(color: Color(0xFF1A1A1A), fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    labelText: 'Recording Title',
                    labelStyle: const TextStyle(color: Color(0xFF8E8E8E), fontFamily: 'Inter'),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF534AB7)),
                    ),
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: _startRecording,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: const BoxDecoration(
                      color: Color(0xFF534AB7),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33534AB7),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Tap to start recording',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8E8E8E),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
