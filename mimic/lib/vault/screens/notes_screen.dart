import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'note_editor_screen.dart';
import '../services/notes_service.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  late Future<List<Note>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  void _loadNotes() {
    setState(() {
      _notesFuture = ref.read(notesServiceProvider).getAllNotes();
    });
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
      body: FutureBuilder<List<Note>>(
        future: _notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: VaultColors.accent),
            );
          }

          final notes = snapshot.data ?? [];

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

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
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
    );
  }
}
