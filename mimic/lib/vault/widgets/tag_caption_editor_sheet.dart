// lib/vault/widgets/tag_caption_editor_sheet.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/vault_tag.dart';

/// Shows an encrypted tag and caption editor bottom sheet.
Future<void> showTagCaptionEditorSheet({
  required BuildContext context,
  required String title,
  required List<String> initialTags,
  String initialCaption = '',
  bool showCaptionField = true,
  required Future<void> Function(List<String> tags, String caption) onSave,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TagCaptionEditorContent(
      title: title,
      initialTags: initialTags,
      initialCaption: initialCaption,
      showCaptionField: showCaptionField,
      onSave: onSave,
    ),
  );
}

class _TagCaptionEditorContent extends StatefulWidget {
  final String title;
  final List<String> initialTags;
  final String initialCaption;
  final bool showCaptionField;
  final Future<void> Function(List<String> tags, String caption) onSave;

  const _TagCaptionEditorContent({
    required this.title,
    required this.initialTags,
    required this.initialCaption,
    this.showCaptionField = true,
    required this.onSave,
  });

  @override
  State<_TagCaptionEditorContent> createState() => _TagCaptionEditorContentState();
}

class _TagCaptionEditorContentState extends State<_TagCaptionEditorContent> {
  late final TextEditingController _captionController;
  late final TextEditingController _tagInputController;
  late final Set<String> _tags;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _tagInputController = TextEditingController();
    _tags = Set<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final normalized = VaultTags.normalize(raw);
    if (normalized.isNotEmpty) {
      setState(() {
        _tags.add(normalized);
        _tagInputController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _handleSave() async {
    if (_tagInputController.text.trim().isNotEmpty) {
      _addTag(_tagInputController.text);
    }
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_tags.toList(), _captionController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.label_outlined, color: VaultColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Vault Locator',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: VaultColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: VaultColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: VaultColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (widget.showCaptionField) ...[
              // Caption Section
              const Text(
                'Private Caption / Note',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _captionController,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add an encrypted note or caption...',
                  hintStyle: const TextStyle(fontFamily: 'Inter', color: VaultColors.textTertiary, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: VaultColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Tags Section
            const Text(
              'Private Tags',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: VaultColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Active Tags Wrap
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _tags.map((tag) {
                    return Chip(
                      label: Text(
                        tag,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: VaultColors.accent,
                        ),
                      ),
                      backgroundColor: VaultColors.accent.withValues(alpha: 0.12),
                      deleteIcon: const Icon(Icons.cancel, size: 16, color: VaultColors.accent),
                      onDeleted: () => _removeTag(tag),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }).toList(),
                ),
              ),

            // Custom tag input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputController,
                    style: const TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Type tag (e.g. #Tax2026)',
                      hintStyle: const TextStyle(fontFamily: 'Inter', color: VaultColors.textTertiary, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onSubmitted: (v) => _addTag(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(backgroundColor: VaultColors.accent),
                  onPressed: () => _addTag(_tagInputController.text),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Presets
            const Text(
              'Quick Suggested Tags:',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: VaultColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: VaultTags.presets.map((preset) {
                final isAdded = _tags.contains(preset);
                return ActionChip(
                  label: Text(
                    preset,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: isAdded ? FontWeight.bold : FontWeight.w500,
                      color: isAdded ? Colors.white : VaultColors.textSecondary,
                    ),
                  ),
                  backgroundColor: isAdded ? VaultColors.accent : const Color(0xFFF3F4F6),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () {
                    if (isAdded) {
                      _removeTag(preset);
                    } else {
                      _addTag(preset);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VaultColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Save Encrypted Details',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
