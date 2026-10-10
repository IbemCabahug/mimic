// mimic/lib/vault/screens/decoy_photos_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../security/decoy_vault_service.dart';

class DecoyPhotosScreen extends ConsumerStatefulWidget {
  const DecoyPhotosScreen({super.key});

  @override
  ConsumerState<DecoyPhotosScreen> createState() => _DecoyPhotosScreenState();
}

class _DecoyPhotosScreenState extends ConsumerState<DecoyPhotosScreen> {
  List<DecoyPhoto> _photos = [];
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final list = await ref.read(decoyVaultServiceProvider).getPhotos();
    if (mounted) {
      setState(() {
        _photos = list;
        _isLoading = false;
      });
    }
  }

  void _showAddDialog() {
    final titleController = TextEditingController();
    final captionController = TextEditingController();
    final tagsController = TextEditingController(text: '#Travel');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Import Photo',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Photo Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: captionController,
              decoration: const InputDecoration(labelText: 'Caption'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(labelText: 'Tags (e.g. #Nature #Family)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              final tags = tagsController.text
                  .split(' ')
                  .where((t) => t.isNotEmpty)
                  .toList();
              final photo = DecoyPhoto(
                id: 'decoy_${DateTime.now().millisecondsSinceEpoch}',
                title: title,
                caption: captionController.text.trim(),
                tags: tags,
                colorValue: 0xFF1976D2,
                createdAt: DateTime.now(),
              );
              await ref.read(decoyVaultServiceProvider).addPhoto(photo);
              Navigator.of(ctx).pop();
              _loadPhotos();
            },
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.accent),
            child: const Text('Save Photo'),
          ),
        ],
      ),
    );
  }

  void _viewPhoto(DecoyPhoto photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Color(photo.colorValue),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(
                  Icons.image,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              photo.title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: VaultColors.textPrimary,
              ),
            ),
            if (photo.caption.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                photo.caption,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: VaultColors.textSecondary,
                ),
              ),
            ],
            if (photo.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: photo.tags
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          backgroundColor: VaultColors.surface,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: VaultColors.error),
                    label: const Text('Delete', style: TextStyle(color: VaultColors.error)),
                    onPressed: () async {
                      await ref.read(decoyVaultServiceProvider).deletePhoto(photo.id);
                      Navigator.of(ctx).pop();
                      _loadPhotos();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(backgroundColor: VaultColors.accent),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _photos.where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.title.toLowerCase().contains(q) ||
          p.caption.toLowerCase().contains(q) ||
          p.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: const Text(
          'Photos',
          style: TextStyle(
            color: VaultColors.accent,
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VaultColors.accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: VaultColors.accent,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add_photo_alternate, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: 'Search photos and tags...',
                prefixIcon: const Icon(Icons.search, color: VaultColors.textTertiary),
                fillColor: VaultColors.surface,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty ? 'No photos in vault' : 'No matches found',
                          style: const TextStyle(color: VaultColors.textSecondary),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, idx) {
                          final photo = filtered[idx];
                          return InkWell(
                            onTap: () => _viewPhoto(photo),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: VaultColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Color(photo.colorValue),
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.photo,
                                          size: 40,
                                          color: Colors.white.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          photo.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: VaultColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          photo.tags.join(' '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            color: VaultColors.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
