import 'dart:io';
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
  String _searchQuery = '';
  String _sortMode = 'date';
  String? _selectedFolder;

  void setDocumentsForTesting(List<DocumentMeta> docs) {
    setState(() {
      documents = docs;
    });
  }

  List<DocumentMeta> _visibleDocuments() {
    Iterable<DocumentMeta> list = documents;
    if (_selectedFolder != null) {
      list = list.where((d) => d.folder == _selectedFolder);
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) => d.fileName.toLowerCase().contains(q));
    }
    final result = list.toList();
    switch (_sortMode) {
      case 'name':
        result.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
        break;
      case 'size':
        result.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case 'type':
        result.sort((a, b) {
          final t = a.fileType.toLowerCase().compareTo(b.fileType.toLowerCase());
          return t != 0 ? t : a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
        });
        break;
      case 'date':
      default:
        result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
    return result;
  }

  Widget _folderChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              color: selected ? Colors.white : VaultColors.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: VaultColors.surface,
      selectedColor: VaultColors.accent,
      showCheckmark: false,
    );
  }

  Widget _buildFolderChips() {
    final folders = documents.map((d) => d.folder).where((f) => f.isNotEmpty).toSet().toList()
      ..sort();
    final hasUnfiled = documents.any((d) => d.folder.isEmpty);
    final chips = <Widget>[
      _folderChip('All', _selectedFolder == null, () => setState(() => _selectedFolder = null)),
    ];
    if (hasUnfiled) {
      chips.add(_folderChip('Unfiled', _selectedFolder == '', () => setState(() => _selectedFolder = '')));
    }
    for (final f in folders) {
      chips.add(_folderChip(f, _selectedFolder == f, () => setState(() => _selectedFolder = f)));
    }
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: chips
            .map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: c))
            .toList(),
      ),
    );
  }

  Future<void> _showMoveToFolder(DocumentMeta doc) async {
    final existingFolders =
        documents.map((d) => d.folder).where((f) => f.isNotEmpty).toSet().toList()..sort();
    final newFolderController = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Move to folder',
            style: TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined, color: VaultColors.textSecondary),
                  title: const Text('Unfiled', style: TextStyle(fontFamily: 'Inter')),
                  onTap: () => Navigator.of(context).pop(''),
                ),
                ...existingFolders.map((f) => ListTile(
                      leading: const Icon(Icons.folder_outlined, color: VaultColors.accent),
                      title: Text(f, style: const TextStyle(fontFamily: 'Inter')),
                      onTap: () => Navigator.of(context).pop(f),
                    )),
                const Divider(),
                TextField(
                  controller: newFolderController,
                  decoration: const InputDecoration(
                      hintText: 'New folder name',
                      hintStyle: TextStyle(fontFamily: 'Inter')),
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              final name = newFolderController.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('Create & Move', style: TextStyle(color: VaultColors.accent)),
          ),
        ],
      ),
    );
    if (chosen != null && mounted) {
      await ref.read(documentVaultServiceProvider).moveDocument(doc.id, chosen);
      await _loadDocuments();
    }
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
      final tempFile = await ref.read(documentVaultServiceProvider).getDocumentToTempFile(doc.id);
      if (tempFile != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(file: tempFile, title: doc.fileName),
          ),
        );
      } else if (tempFile == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load document')),
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
              : Builder(
                  builder: (context) {
                    final visible = _visibleDocuments();
                    return Column(
                      children: [
                        _buildFolderChips(),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                  style: const TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'Search documents',
                                    hintStyle: const TextStyle(fontFamily: 'Inter', color: VaultColors.textTertiary),
                                    prefixIcon: const Icon(Icons.search, color: VaultColors.textTertiary),
                                    filled: true,
                                    fillColor: VaultColors.surface,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.sort, color: VaultColors.textSecondary),
                                initialValue: _sortMode,
                                onSelected: (v) => setState(() => _sortMode = v),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'date', child: Text('Newest first')),
                                  PopupMenuItem(value: 'name', child: Text('Name (A–Z)')),
                                  PopupMenuItem(value: 'size', child: Text('Largest first')),
                                  PopupMenuItem(value: 'type', child: Text('File type')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? Center(
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
                                        'No documents match your search',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: VaultColors.textTertiary,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final doc = visible[index];
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
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: VaultColors.textTertiary, size: 20),
                                onSelected: (v) {
                                  if (v == 'move') _showMoveToFolder(doc);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'move', child: Text('Move to folder')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                                  },
                                ),
                        ),
                      ],
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

class PdfViewerScreen extends StatefulWidget {
  final File file;
  final String title;

  const PdfViewerScreen({super.key, required this.file, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  @override
  void dispose() {
    try {
      if (widget.file.existsSync()) {
        widget.file.deleteSync();
      }
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: widget.title,
      showLockButton: false,
      body: SfPdfViewer.file(widget.file),
    );
  }
}