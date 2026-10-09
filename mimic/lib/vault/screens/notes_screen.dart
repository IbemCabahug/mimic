import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'note_editor_screen.dart';
import '../services/notes_service.dart';
import '../services/pro_status_service.dart';
import '../crypto/vault_crypto.dart';
import '../widgets/vault_scaffold.dart';
import '../widgets/vault_search_bar.dart';
import '../widgets/paywall_sheet.dart';
import '../../core/theme/app_theme.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  late Future<List<Note>> _notesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTag;
  List<Note> _cachedNotes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadNotes() {
    setState(() {
      _notesFuture = ref.read(notesServiceProvider).getAllNotes().then((list) {
        _cachedNotes = list;
        return list;
      });
    });
  }

  List<String> _extractAllTags(List<Note> notes) {
    final set = <String>{};
    for (final n in notes) {
      set.addAll(n.tags);
    }
    return set.toList();
  }

  Future<bool?> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Note',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this note?',
          style: TextStyle(color: VaultColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: VaultColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(notesServiceProvider).deleteNote(note.id);
      HapticFeedback.mediumImpact();
      _loadNotes();
      return true;
    }
    return false;
  }

  void _openNote(Note note) async {
    final decryptedBody = note.encryptedBody;
    if (!mounted) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note, initialBody: decryptedBody),
      ),
    );
    if (result == true) {
      _loadNotes();
    }
  }

  void _createNewNote() async {
    final now = DateTime.now();
    final newNote = Note(
      id: now.millisecondsSinceEpoch.toString(),
      title: 'Untitled Note',
      encryptedBody: '',
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(notesServiceProvider).addNote(newNote);
    if (!mounted) return;
    final createdNote = Note(
      id: newNote.id,
      title: newNote.title,
      encryptedBody: newNote.encryptedBody,
      createdAt: newNote.createdAt,
      updatedAt: newNote.updatedAt,
    );
    _openNote(createdNote);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getPreview(String encryptedBody) {
    try {
      if (encryptedBody.isEmpty) return 'No content';
      if (encryptedBody.length <= 80) return encryptedBody;
      return '${encryptedBody.substring(0, 80)}...';
    } catch (e) {
      return 'Encrypted note';
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Notes',
      floatingActionButton: AnimatedFAB(
        child: FloatingActionButton.extended(
          onPressed: _createNewNote,
          backgroundColor: VaultColors.accent,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'New Note',
            style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: Column(
        children: [
          VaultSearchBar(
            controller: _searchController,
            hintText: 'Search notes by title, text, #tag...',
            onQueryChanged: (v) => setState(() => _searchQuery = v),
            onClear: () => setState(() {
              _searchController.clear();
              _searchQuery = '';
            }),
            selectedTag: _selectedTag,
            onTagSelected: (t) => setState(() => _selectedTag = t),
            availableTags: _extractAllTags(_cachedNotes),
            isPro: ref.watch(isProProvider).value ?? false,
            onProRequired: () => showPaywallSheet(context),
          ),
          Expanded(
            child: FutureBuilder<List<Note>>(
              future: _notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: VaultColors.accent),
            );
          }

          final notes = snapshot.data ?? [];

          var visibleNotes = notes;
          if (_selectedTag != null && _selectedTag!.isNotEmpty) {
            visibleNotes = visibleNotes.where((n) => n.tags.contains(_selectedTag)).toList();
          }
          final q = _searchQuery.trim().toLowerCase();
          if (q.isNotEmpty) {
            visibleNotes = visibleNotes.where((n) {
              final titleMatch = n.title.toLowerCase().contains(q);
              final bodyMatch = n.encryptedBody.toLowerCase().contains(q);
              final tagMatch = n.tags.any((t) => t.toLowerCase().contains(q));
              return titleMatch || bodyMatch || tagMatch;
            }).toList();
          }

          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.note_outlined,
                    size: 80,
                    color: VaultColors.accent.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notes yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: VaultColors.textTertiary,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create your first note',
                    style: TextStyle(
                      fontSize: 14,
                      color: VaultColors.textTertiary.withValues(alpha: 0.7),
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            );
          }

          if (visibleNotes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 80,
                    color: VaultColors.accent.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notes match your search',
                    style: TextStyle(
                      fontSize: 18,
                      color: VaultColors.textTertiary,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: visibleNotes.length,
            itemBuilder: (context, index) {
              final note = visibleNotes[index];
              final preview = _getPreview(note.encryptedBody);
              final dateStr = _formatDate(note.updatedAt);

              return Dismissible(
                key: Key(note.id),
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
                confirmDismiss: (direction) => _deleteNote(note),
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
                    title: Text(
                      note.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: VaultColors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preview,
                            style: const TextStyle(
                              fontSize: 13,
                              color: VaultColors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (note.tags.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: note.tags.map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: VaultColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'Inter',
                                    color: VaultColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )).toList(),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: VaultColors.textTertiary.withValues(alpha: 0.8),
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                    onTap: () => _openNote(note),
                  ),
                ),
              );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}
