// lib/vault/screens/note_editor_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> with WidgetsBindingObserver {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  bool _hasChanges = false;
  Timer? _autoSaveTimer;
  bool _previewMode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleController = TextEditingController(text: widget.note.title);
    _bodyController = TextEditingController(text: widget.initialBody);
    _titleController.addListener(_onContentChanged);
    _bodyController.addListener(_onContentChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _saveNote();
    }
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
    if (mounted) setState(() => _isSaving = true);
    try {
      await ref.read(notesServiceProvider).updateNote(updatedNote);
      if (mounted) setState(() { _hasChanges = false; _isSaving = false; });
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    await _saveNote();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String _statusText() {
    if (_isSaving) return 'Saving…';
    if (!_hasChanges) return 'Saved';
    return '';
  }

  void _wrapSelection(String left, String right) {
    final text = _bodyController.text;
    final sel = _bodyController.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$left$selected$right');
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: start + left.length + selected.length + right.length),
    );
  }

  void _insertLinePrefix(String prefix) {
    final text = _bodyController.text;
    final sel = _bodyController.selection;
    final pos = sel.start < 0 ? text.length : sel.start;
    final lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFCFCFCF))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.format_bold), color: const Color(0xFF3A2DB0), onPressed: () => _wrapSelection('**', '**')),
            IconButton(icon: const Icon(Icons.format_italic), color: const Color(0xFF3A2DB0), onPressed: () => _wrapSelection('*', '*')),
            IconButton(icon: const Icon(Icons.title), color: const Color(0xFF3A2DB0), onPressed: () => _insertLinePrefix('# ')),
            IconButton(icon: const Icon(Icons.format_list_bulleted), color: const Color(0xFF3A2DB0), onPressed: () => _insertLinePrefix('- ')),
            IconButton(icon: const Icon(Icons.check_box_outlined), color: const Color(0xFF3A2DB0), onPressed: () => _insertLinePrefix('- [ ] ')),
            IconButton(icon: const Icon(Icons.code), color: const Color(0xFF3A2DB0), onPressed: () => _wrapSelection('`', '`')),
          ],
        ),
      ),
    );
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
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF3A2DB0), size: 20),
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
              hintStyle: TextStyle(color: Color(0xFF5C5C5C), fontFamily: 'Inter'),
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  _statusText(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C), fontFamily: 'Inter'),
                ),
              ),
            ),
            IconButton(
              icon: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF3A2DB0)),
              onPressed: () => setState(() => _previewMode = !_previewMode),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _previewMode
                  ? Markdown(
                      data: _bodyController.text.trim().isEmpty
                          ? '*Nothing to preview*'
                          : _bodyController.text,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: TextField(
                        controller: _bodyController,
                        cursorColor: const Color(0xFF3A2DB0),
                        style: const TextStyle(fontSize: 17, color: Color(0xFF111111), fontFamily: 'Inter', height: 1.6, fontWeight: FontWeight.w600),
                        maxLines: null,
                        expands: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Start typing… (Markdown supported)',
                          hintStyle: TextStyle(color: Color(0xFF5C5C5C), fontFamily: 'Inter'),
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
            ),
            if (!_previewMode) _buildToolbar(),
          ],
        ),
      ),
    );
  }
}
