import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../widgets/vault_scaffold.dart';
import '../services/document_vault_service.dart';
import '../../core/theme/app_theme.dart';

class DocumentVaultScreen extends ConsumerStatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  ConsumerState<DocumentVaultScreen> createState() => DocumentVaultScreenState();
}

class DocumentVaultScreenState extends ConsumerState<DocumentVaultScreen> {
  List<DocumentMeta> documents = [];
  bool _isLoading = true;

  void setDocumentsForTesting(List<DocumentMeta> docs) {
    setState(() {
      documents = docs;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    final loaded = await ref.read(documentVaultServiceProvider).listDocuments();
    if (mounted) {
      setState(() {
        documents = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _importDocument() async {
    try {
      await ref.read(documentVaultServiceProvider).importDocument();
      await _loadDocuments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  Future<void> _createTextNote() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'New Text Note',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter note title',
            hintStyle: TextStyle(fontFamily: 'Inter'),
          ),
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create', style: TextStyle(color: VaultColors.accent)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final title = controller.text.trim();
      final docId = await ref.read(documentVaultServiceProvider).createTextNote(title, '');
      final noteBytes = await ref.read(documentVaultServiceProvider).getDocumentBytes(docId);
      if (noteBytes != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DocumentEditorScreen(
              documentId: docId,
              initialContent: '',
              isNew: true,
            ),
          ),
        );
        await _loadDocuments();
      }
    }
  }

  Future<void> _showImportOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: VaultColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.file_present, color: Colors.white),
                ),
                title: const Text('Import File', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _importDocument();
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: VaultColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.text_snippet, color: Colors.white),
                ),
                title: const Text('New Text Note', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(context).pop();
                  _createTextNote();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDocument(DocumentMeta doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Document',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'Are you sure you want to permanently delete this document?',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: VaultColors.error, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(documentVaultServiceProvider).deleteDocument(doc.id);
      HapticFeedback.mediumImpact();
      await _loadDocuments();
    }
  }

  Future<void> _openDocument(DocumentMeta doc) async {
    if (doc.fileType == 'txt' || doc.isTextNote) {
      final content = await ref.read(documentVaultServiceProvider).getTextNote(doc.id);
      if (content != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DocumentEditorScreen(
              documentId: doc.id,
              initialContent: content,
              isNew: false,
            ),
          ),
        );
        await _loadDocuments();
      }
    } else if (doc.fileType == 'pdf') {
      final bytes = await ref.read(documentVaultServiceProvider).getDocumentBytes(doc.id);
      if (bytes != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(bytes: bytes, title: doc.fileName),
          ),
        );
      }
    } else if (doc.fileType == 'docx' || doc.fileType == 'xlsx') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Preview Not Available',
            style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
          content: const Text(
            'Preview not available for this file type.',
            style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: VaultColors.accent)),
            ),
          ],
        ),
      );
    }
  }

  IconData _getDocIcon(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'txt':
        return Icons.text_snippet;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getDocColor(String type) {
    switch (type) {
      case 'pdf':
        return const Color(0xFFD85A30);
      case 'txt':
        return const Color(0xFF1D9E75);
      case 'doc':
      case 'docx':
        return const Color(0xFF378ADD);
      case 'xlsx':
        return const Color(0xFF2196F3);
      default:
        return VaultColors.accent;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Documents',
      floatingActionButton: AnimatedFAB(
        child: FloatingActionButton.extended(
          onPressed: _showImportOptions,
          backgroundColor: VaultColors.accent,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Add',
            style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : documents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 80,
                        color: VaultColors.accent.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No documents yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: VaultColors.textTertiary,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add your first document',
                        style: TextStyle(
                          fontSize: 14,
                          color: VaultColors.textTertiary.withValues(alpha: 0.7),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final doc = documents[index];
                    final docColor = _getDocColor(doc.fileType);

                    return Dismissible(
                      key: Key(doc.id),
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
                      confirmDismiss: (direction) => _deleteDocument(doc).then((_) => false),
                      onDismissed: (direction) {
                        HapticFeedback.mediumImpact();
                      },
                      child: Material(
                        color: VaultColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openDocument(doc),
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
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: docColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_getDocIcon(doc.fileType), color: docColor),
                              ),
                              title: Text(
                                doc.fileName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: VaultColors.textPrimary,
                                  fontFamily: 'Inter',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${doc.fileType.toUpperCase()} • ${_formatSize(doc.sizeBytes)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: VaultColors.textSecondary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: VaultColors.textTertiary, size: 20),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class DocumentEditorScreen extends ConsumerStatefulWidget {
  final String documentId;
  final String initialContent;
  final bool isNew;

  const DocumentEditorScreen({
    super.key,
    required this.documentId,
    required this.initialContent,
    required this.isNew,
  });

  @override
  ConsumerState<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() {
      setState(() => _hasChanges = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(documentVaultServiceProvider).updateTextNote(
      widget.documentId,
      _controller.text,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Text Note',
      showLockButton: false,
      floatingActionButton: _hasChanges
          ? AnimatedFAB(
              child: FloatingActionButton(
                onPressed: _save,
                backgroundColor: VaultColors.accent,
                child: const Icon(Icons.save, color: Colors.white),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          decoration: const InputDecoration(
            hintText: 'Start typing...',
            border: InputBorder.none,
          ),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: VaultColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String title;

  const PdfViewerScreen({super.key, required this.bytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: title,
      showLockButton: false,
      body: SfPdfViewer.memory(bytes),
    );
  }
}