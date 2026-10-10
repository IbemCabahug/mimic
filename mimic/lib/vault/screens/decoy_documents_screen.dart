// mimic/lib/vault/screens/decoy_documents_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../security/decoy_vault_service.dart';

class DecoyDocumentsScreen extends ConsumerStatefulWidget {
  const DecoyDocumentsScreen({super.key});

  @override
  ConsumerState<DecoyDocumentsScreen> createState() => _DecoyDocumentsScreenState();
}

class _DecoyDocumentsScreenState extends ConsumerState<DecoyDocumentsScreen> {
  List<DecoyDocument> _docs = [];
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    final list = await ref.read(decoyVaultServiceProvider).getDocuments();
    if (mounted) {
      setState(() {
        _docs = list;
        _isLoading = false;
      });
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final tagsController = TextEditingController(text: '#Important');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Import Document',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Document Name (.pdf)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(labelText: 'Tags (e.g. #Work #Receipt)'),
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
              var name = nameController.text.trim();
              if (name.isEmpty) return;
              if (!name.endsWith('.pdf')) name = '$name.pdf';
              final tags = tagsController.text
                  .split(' ')
                  .where((t) => t.isNotEmpty)
                  .toList();
              final doc = DecoyDocument(
                id: 'decoy_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                fileSize: 1250000,
                tags: tags,
                updatedAt: DateTime.now(),
              );
              await ref.read(decoyVaultServiceProvider).addDocument(doc);
              Navigator.of(ctx).pop();
              _loadDocs();
            },
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.accent),
            child: const Text('Save Document'),
          ),
        ],
      ),
    );
  }

  void _viewDoc(DecoyDocument doc) {
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: VaultColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(doc.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: VaultColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (doc.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                children: doc.tags
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          backgroundColor: VaultColors.surface,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: VaultColors.error),
                    label: const Text('Delete', style: TextStyle(color: VaultColors.error)),
                    onPressed: () async {
                      await ref.read(decoyVaultServiceProvider).deleteDocument(doc.id);
                      Navigator.of(ctx).pop();
                      _loadDocs();
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
    final filtered = _docs.where((d) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: const Text(
          'Documents',
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
        child: const Icon(Icons.note_add_outlined, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: 'Search documents and tags...',
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
                          _query.isEmpty ? 'No documents in vault' : 'No matching documents',
                          style: const TextStyle(color: VaultColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final doc = filtered[idx];
                          return InkWell(
                            onTap: () => _viewDoc(doc),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: VaultColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          doc.name,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: VaultColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${(doc.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB • ${doc.tags.join(" ")}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            color: VaultColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: VaultColors.textTertiary),
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
