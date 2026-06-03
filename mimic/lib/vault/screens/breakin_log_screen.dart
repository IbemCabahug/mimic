import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/vault_crypto.dart';
import '../security/breakin_log.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class BreakInLogScreen extends ConsumerStatefulWidget {
  const BreakInLogScreen({super.key});

  @override
  ConsumerState<BreakInLogScreen> createState() => _BreakInLogScreenState();
}

class _BreakInLogScreenState extends ConsumerState<BreakInLogScreen> {
  List<BreakInLog> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await BreakInLogService.getLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteLog(String id) async {
    await BreakInLogService.deleteLog(id);
    _loadLogs();
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Logs',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: VaultColors.accent),
            )
          : _logs.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Dismissible(
                      key: Key(log.id),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: VaultColors.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: VaultColors.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        _deleteLog(log.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Log deleted')),
                        );
                      },
                      child: _buildLogCard(log),
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
            'No intrusion attempts detected',
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

  Widget _buildLogCard(BreakInLog log) {
    final hasPhoto = log.encryptedPhotoPath != null && log.encryptedPhotoPath!.isNotEmpty;

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 50,
            height: 50,
            color: VaultColors.accent.withValues(alpha: 0.05),
            child: hasPhoto
                ? DecryptedThumbnail(photoPath: log.encryptedPhotoPath!)
                : const Icon(Icons.lock_outline, color: VaultColors.accent),
          ),
        ),
        title: Text(
          'Failed Login Attempt (${log.attemptCount})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: VaultColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatDateTime(log.timestamp),
            style: const TextStyle(
              fontSize: 12,
              color: VaultColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ),
        trailing: hasPhoto
            ? const Icon(Icons.chevron_right, color: VaultColors.textTertiary)
            : null,
        onTap: hasPhoto
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullScreenPhotoViewer(
                      photoPath: log.encryptedPhotoPath!,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }
}

class DecryptedThumbnail extends ConsumerWidget {
  final String photoPath;

  const DecryptedThumbnail({super.key, required this.photoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crypto = ref.watch(vaultCryptoProvider);
    return FutureBuilder<Uint8List>(
      future: () async {
        final file = File(photoPath);
        if (!await file.exists()) {
          throw Exception('File does not exist');
        }
        final encryptedBytes = await file.readAsBytes();
        return await crypto.decryptBytes(encryptedBytes);
      }(),
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
            child: Icon(Icons.broken_image, color: VaultColors.error, size: 20),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: 50,
          height: 50,
        );
      },
    );
  }
}

class FullScreenPhotoViewer extends StatelessWidget {
  final String photoPath;

  const FullScreenPhotoViewer({super.key, required this.photoPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Consumer(
            builder: (context, ref, _) {
              final crypto = ref.watch(vaultCryptoProvider);
              return FutureBuilder<Uint8List>(
                future: () async {
                  final file = File(photoPath);
                  final encryptedBytes = await file.readAsBytes();
                  return await crypto.decryptBytes(encryptedBytes);
                }(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator(color: Colors.white);
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Icon(Icons.broken_image, color: Colors.white, size: 48);
                  }
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
