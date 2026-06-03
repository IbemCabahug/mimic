// lib/vault/screens/note_editor_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notes_service.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final String initialBody;

  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.initialBody,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  bool _hasChanges = false;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _bodyController = TextEditingController(text: widget.initialBody);
    _titleController.addListener(_onContentChanged);
    _bodyController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), _saveNote);
  }

  Future<void> _saveNote() async {
    if (!_hasChanges) return;
    final updatedNote = Note(
      id: widget.note.id,
      title: _titleController.text.trim().isEmpty ? 'Untitled Note' : _titleController.text.trim(),
      encryptedBody: _bodyController.text,
      createdAt: widget.note.createdAt,
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(notesServiceProvider).updateNote(updatedNote);
      if (mounted) {
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      // Silently fail auto-save
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    await _saveNote();
    return true;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop) {
          navigator.pop(true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1EFE8),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF534AB7), size: 20),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final shouldPop = await _onWillPop();
              if (shouldPop) {
                navigator.pop(true);
              }
            },
          ),
          title: TextField(
            controller: _titleController,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
              fontFamily: 'Inter',
            ),
            decoration: const InputDecoration(
              hintText: 'Note title',
              hintStyle: TextStyle(color: Color(0xFF8E8E8E), fontFamily: 'Inter'),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            if (_hasChanges)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFF534AB7),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF534AB7)),
                  ),
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
            controller: _bodyController,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF1A1A1A),
              fontFamily: 'Inter',
              height: 1.6,
            ),
            maxLines: null,
            expands: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Start typing...',
              hintStyle: TextStyle(
                color: Color(0xFF8E8E8E),
                fontFamily: 'Inter',
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}
