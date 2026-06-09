import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/intruder_service.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class BreakInLogScreen extends ConsumerStatefulWidget {
  const BreakInLogScreen({super.key});

  @override
  ConsumerState<BreakInLogScreen> createState() => _BreakInLogScreenState();
}

class _BreakInLogScreenState extends ConsumerState<BreakInLogScreen> {
  List<IntruderEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final entries = await IntruderService().getIntruderLog();
      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteEntry(String filename) async {
    await IntruderService().deleteIntruderEntry(filename);
    _loadEntries();
  }

  String _formatTimestamp(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month $day, $year — $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Intruder Logs',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: VaultColors.accent),
            )
          : _entries.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
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
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 50,
                            height: 50,
                            color: VaultColors.accent.withValues(alpha: 0.05),
                            child: _BlurredThumbnail(filename: entry.filename),
                          ),
                        ),
                        title: const Text(
                          'Failed Login Attempt',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: VaultColors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _formatTimestamp(entry.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: VaultColors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: VaultColors.error, size: 20),
                          onPressed: () => _deleteEntry(entry.filename),
                        ),
                        onTap: () => _showFullImage(entry.filename),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: VaultColors.accent.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 72,
              color: VaultColors.accent,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No intrusion attempts recorded',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VaultColors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String filename) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            FutureBuilder<Uint8List>(
              future: IntruderService().decryptIntruderImage(filename),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(
                    child: Icon(Icons.broken_image,
                        color: Colors.white, size: 48),
                  );
                }
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    cacheWidth: 1080,
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredThumbnail extends ConsumerWidget {
  final String filename;

  const _BlurredThumbnail({required this.filename});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uint8List>(
      future: IntruderService().decryptIntruderImage(filename),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VaultColors.accent,
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Icon(Icons.broken_image,
                color: VaultColors.error, size: 20),
          );
        }
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: 50,
            height: 50,
            cacheWidth: 80,
            cacheHeight: 80,
          ),
        );
      },
    );
  }
}
