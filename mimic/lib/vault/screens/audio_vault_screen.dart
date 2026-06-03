import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_vault_service.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';
import 'audio_recorder_screen.dart';

class AudioVaultScreen extends ConsumerStatefulWidget {
  const AudioVaultScreen({super.key});

  @override
  ConsumerState<AudioVaultScreen> createState() => _AudioVaultScreenState();
}

class _AudioVaultScreenState extends ConsumerState<AudioVaultScreen> {
  List<AudioMeta> _recordings = [];
  bool _isLoading = true;
  String? _currentlyPlayingId;
  double _playbackProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final recordings = await ref.read(audioVaultServiceProvider).getAllAudio();
    if (mounted) {
      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    }
  }

  Future<bool?> _deleteRecording(AudioMeta recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Recording',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this recording?',
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
      await ref.read(audioVaultServiceProvider).deleteAudio(recording.id);
      HapticFeedback.mediumImpact();
      await _loadRecordings();
    }
    return confirmed;
  }

  Future<void> _playRecording(AudioMeta recording) async {
    if (_currentlyPlayingId == recording.id) {
      setState(() {
        _currentlyPlayingId = null;
        _playbackProgress = 0.0;
      });
      return;
    }

    setState(() {
      _currentlyPlayingId = recording.id;
      _playbackProgress = 0.0;
    });

    final encryptedBytes = await ref.read(audioVaultServiceProvider).getAudio(recording.id);
    if (encryptedBytes == null) {
      setState(() {
        _currentlyPlayingId = null;
        _playbackProgress = 0.0;
      });
      return;
    }

    for (double i = 0; i <= 1.0; i += 0.05) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || _currentlyPlayingId != recording.id) return;
      setState(() => _playbackProgress = i);
    }

    setState(() {
      _currentlyPlayingId = null;
      _playbackProgress = 0.0;
    });
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Audio',
      floatingActionButton: AnimatedFAB(
        child: FloatingActionButton(
          onPressed: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AudioRecorderScreen()),
            );
            if (result == true) {
              await _loadRecordings();
            }
          },
          backgroundColor: VaultColors.accent,
          child: const Icon(Icons.mic, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _recordings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.audio_file_outlined,
                        size: 80,
                        color: VaultColors.accent.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No recordings yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: VaultColors.textTertiary,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to record your first audio',
                        style: TextStyle(
                          fontSize: 14,
                          color: VaultColors.textTertiary.withValues(alpha: 0.7),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    final isPlaying = _currentlyPlayingId == recording.id;

                    return Dismissible(
                      key: Key(recording.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: VaultColors.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      confirmDismiss: (direction) => _deleteRecording(recording),
                      onDismissed: (direction) {
                        HapticFeedback.mediumImpact();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: VaultColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: VaultColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            recording.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: VaultColors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                _formatDuration(recording.durationMs),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: VaultColors.textSecondary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(recording.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: VaultColors.textTertiary.withValues(alpha: 0.8),
                                  fontFamily: 'Inter',
                                ),
                              ),
                              if (isPlaying) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _playbackProgress,
                                    backgroundColor: const Color(0xFFE0E0E0),
                                    valueColor: const AlwaysStoppedAnimation<Color>(VaultColors.accent),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _playRecording(recording),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
