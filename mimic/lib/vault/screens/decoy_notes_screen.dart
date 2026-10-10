// mimic/lib/vault/screens/decoy_notes_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../security/decoy_vault_service.dart';

class DecoyNotesScreen extends ConsumerStatefulWidget {
  const DecoyNotesScreen({super.key});

  @override
  ConsumerState<DecoyNotesScreen> createState() => _DecoyNotesScreenState();
}

class _DecoyNotesScreenState extends ConsumerState<DecoyNotesScreen> {
  List<DecoyNote> _notes = [];
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final list = await ref.read(decoyVaultServiceProvider).getNotes();
    if (mounted) {
      setState(() {
        _notes = list;
        _isLoading = false;
      });
    }
  }

  void _openNoteEditor([DecoyNote? existing]) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final contentController = TextEditingController(text: existing?.content ?? '');
    final tagsController = TextEditingController(text: existing?.tags.join(' ') ?? '#Personal');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 24,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'New Note' : 'Edit Note',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Note Content'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: 'Tags (e.g. #Shopping #Work)'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (existing != null) ...[
                    OutlinedButton(
                      onPressed: () async {
                        await ref.read(decoyVaultServiceProvider).deleteNote(existing.id);
                        Navigator.of(ctx).pop();
                        _loadNotes();
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: VaultColors.error),
                      child: const Text('Delete'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;
                        final tags = tagsController.text
                            .split(' ')
                            .where((t) => t.isNotEmpty)
                            .toList();
                        final note = DecoyNote(
                          id: existing?.id ?? 'decoy_${DateTime.now().millisecondsSinceEpoch}',
                          title: title,
                          content: contentController.text.trim(),
                          tags: tags,
                          updatedAt: DateTime.now(),
                        );
                        await ref.read(decoyVaultServiceProvider).saveNote(note);
                        Navigator.of(ctx).pop();
                        _loadNotes();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: VaultColors.accent),
                      child: const Text('Save Note'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _notes.where((n) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: const Text(
          'Notes',
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
        onPressed: () => _openNoteEditor(),
        child: const Icon(Icons.note_add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: 'Search notes and tags...',
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
                          _query.isEmpty ? 'No notes in vault' : 'No matching notes',
                          style: const TextStyle(color: VaultColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final note = filtered[idx];
                          return InkWell(
                            onTap: () => _openNoteEditor(note),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: VaultColors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          note.title,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: VaultColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.edit_outlined, size: 16, color: VaultColors.textTertiary),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    note.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      color: VaultColors.textSecondary,
                                    ),
                                  ),
                                  if (note.tags.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      children: note.tags
                                          .map((t) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: VaultColors.accent.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  t,
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 11,
                                                    color: VaultColors.accent,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],
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
