import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../widgets/vault_scaffold.dart';
import '../widgets/import_activity_button.dart';
import '../security/vault_error_ui.dart';
import '../crypto/vault_crypto.dart';
import '../security/auto_lock.dart';
import '../services/document_vault_service.dart';
import '../services/import_progress.dart';
import '../../core/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';

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

  /// One restore session, same model and same pill as the video vault (F26).
  /// A document restore is a single item, so the row count is always 1: the
  /// pill reads "Restoring 1/1" and the row says 'Restoring' while the decrypt
  /// and the SAF write run. Its bar is INDETERMINATE on purpose — the vault
  /// read is a whole-file in-memory decrypt and the copy out goes through the
  /// system file picker, so there is no byte stream to measure; NN/g's rule is
  /// a looped indicator for a short unknown wait and a percent only when the
  /// wait is longer AND measurable, and inventing a percent would be a lie.
  final ImportSession _restoreSession = ImportSession();
  Timer? _restoreLingerTimer;

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
                  title: const Text('Unfiled', style: TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary)),
                  onTap: () => Navigator.of(context).pop(''),
                ),
                ...existingFolders.map((f) => ListTile(
                      leading: const Icon(Icons.folder_outlined, color: VaultColors.accent),
                      title: Text(f, style: const TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary)),
                      onTap: () => Navigator.of(context).pop(f),
                    )),
                const Divider(),
                TextField(
                  controller: newFolderController,
                  decoration: const InputDecoration(
                      hintText: 'New folder name',
                      hintStyle: TextStyle(fontFamily: 'Inter')),
                  style: const TextStyle(fontFamily: 'Inter', color: VaultColors.textPrimary),
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

  Future<void> _shareDocument(DocumentMeta doc) async {
    final service = ref.read(documentVaultServiceProvider);
    await service.cleanupShareTemp(); // clear any stale temp first
    final file = await service.getDocumentForSharing(doc);
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to prepare file for sharing')),
        );
      }
      return;
    }
    try {
      await Share.shareXFiles([XFile(file.path)], subject: doc.fileName);
    } finally {
      await service.cleanupShareTemp(); // delete decrypted temp after sharing
    }
  }

  @override
  void dispose() {
    _restoreLingerTimer?.cancel();
    _restoreSession.dispose();
    super.dispose();
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

  /// Asks the user whether the ORIGINAL document should be removed after a
  /// successful import. Opt-in per import (never automatic): deleting a source
  /// file outside the vault is destructive, and provider support varies — the
  /// outcome message must be honest about that.
  Future<bool> _askRemoveOriginal() async {
    var remove = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Remove original after import?',
            style: TextStyle(
                color: VaultColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mimic saves an encrypted copy in the vault. The original file '
                'stays where it is unless you ask to remove it here.',
                style: TextStyle(
                    color: VaultColors.textSecondary, fontFamily: 'Inter'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Removal goes through your device\'s file manager and may not '
                'be possible for every file (e.g. some cloud or read-only '
                'locations). If it cannot be removed, the original is kept '
                'and Mimic will say so.',
                style: TextStyle(
                    fontSize: 12,
                    color: VaultColors.textTertiary,
                    fontFamily: 'Inter'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: remove,
                onChanged: (v) => setDialogState(() => remove = v ?? false),
                activeColor: VaultColors.accent,
                // The unchecked box was nearly invisible on the white dialog —
                // M3's default border is a low-contrast grey, and the operator
                // reported not seeing the checkbox at all. 2px black reads as
                // a checkbox at a glance.
                side: const BorderSide(width: 2, color: Colors.black),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Also remove the original',
                  style: TextStyle(
                      color: VaultColors.textPrimary, fontFamily: 'Inter'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: VaultColors.textTertiary, fontFamily: 'Inter')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Import',
                  style: TextStyle(
                      color: VaultColors.accent, fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );
    return remove;
  }

  Future<void> _importDocument() async {
    // The removal question comes BEFORE the picker: once the system sheet is
    // dismissed we already hold the file, and asking about deletion after the
    // vault copy exists reads like a nagging second prompt.
    var removeOriginal = false;
    if (mounted) {
      removeOriginal = await _askRemoveOriginal();
    }
    AutoLock().beginProtectedOperation();
    try {
      // The truth about document imports, verified against file_picker 10.3.10
      // (see importDocument): the picker copies the file into OUR cache dir and
      // hands back that copy's path, so the vault save never touches the user's
      // real file. With the opt-in above, the ORIGINAL is then removed through
      // SAF (DocumentsContract), and the outcome below reports exactly what
      // happened — removed, kept by choice, or kept because the source would
      // not allow it. Nothing is described as secure erasure: device-level
      // deletion plus any cloud copies are outside Mimic's reach.
      final service = ref.read(documentVaultServiceProvider);
      final result = removeOriginal
          ? await service.importDocumentAndRemoveOriginal()
          : await service.importDocument().then((r) => (
                id: r.id,
                tempCopyRemoved: r.tempCopyRemoved,
                originalRemoved: false,
                originalNote: null as String?,
              ));
      await _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(result.originalRemoved
                    ? 'Saved to vault · Original removed'
                    : 'Saved to vault'),
                const SizedBox(height: 2),
                if (result.originalNote != null)
                  Text(result.originalNote!,
                      style: const TextStyle(fontSize: 12)),
                if (!result.originalRemoved && result.originalNote == null)
                  const Text(
                    'The file you picked is still in your own storage. Remove '
                    'it there if you want it gone.',
                    style: TextStyle(fontSize: 12),
                  ),
                if (result.tempCopyRemoved) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Mimic removed its own temporary copy.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      AutoLock().endProtectedOperation();
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
      Uint8List? noteBytes;
      try {
        noteBytes = await ref.read(documentVaultServiceProvider).getDocumentBytes(docId);
      } on SystemKeyMissingException catch (_) {
        if (!mounted) return;
        showSecureKeyLostSnackBar(context);
      }
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

  /// Moves a document back OUT of the vault: decrypts it and saves a readable
  /// copy wherever the user picks (Android SAF). The vault copy is removed
  /// only after the save is confirmed. Every outcome gets an honest message —
  /// including the partial one where the copy was written but the vault
  /// delete failed, because a silent duplicate defeats the vault.
  Future<void> _restoreDocument(DocumentMeta doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restore to Device',
          style: TextStyle(color: VaultColors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: const Text(
          'This decrypts the document and saves a readable copy to a location you choose. Anyone with access to the device can read it there. After the save succeeds, it will be removed from the vault.',
          style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore', style: TextStyle(color: VaultColors.accent, fontFamily: 'Inter')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The restore is visible work now: the same pill the video vault uses sits
    // above the Add FAB with a 'Restoring' row for this file, so the screen
    // never looks dead while the decrypt and the save run. A document has no
    // measurable byte stream (whole-file decrypt in memory, then a copy out
    // through the system picker), so the row carries no percent — an honest
    // moving bar instead of an invented number.
    _restoreLingerTimer?.cancel();
    _restoreSession.beginRestore([doc.fileName]);
    _restoreSession.markRestoring(0, 1);

    final outcome =
        await ref.read(documentVaultServiceProvider).restoreDocumentToDisk(doc.id);
    if (!mounted) return;
    // Map the outcome onto the row so the pill tells the same story as the
    // snackbar below. 'cancelled' (picker dismissed) is not a failure and not
    // a save either: the vault copy is untouched, so the row is cleared rather
    // than marked 'Failed'.
    switch (outcome) {
      case DocumentRestoreOutcome.restored:
        _restoreSession.markSaved(0);
        break;
      case DocumentRestoreOutcome.restoredButVaultCopyRemains:
        _restoreSession.markSavedOriginalKept(0);
        break;
      case DocumentRestoreOutcome.saveFailed:
        _restoreSession.markFailed(0, 'Could not save the document');
        break;
      case DocumentRestoreOutcome.cancelled:
        _restoreSession.clear();
        break;
    }
    final String message;
    switch (outcome) {
      case DocumentRestoreOutcome.restored:
        message = 'Document restored. The vault copy was removed.';
        break;
      case DocumentRestoreOutcome.cancelled:
        message = 'Restore cancelled. The vault copy was kept.';
        break;
      case DocumentRestoreOutcome.saveFailed:
        message = 'Could not save the document. The vault copy was kept.';
        break;
      case DocumentRestoreOutcome.restoredButVaultCopyRemains:
        message =
            'Document was saved, but the vault copy could not be deleted. Delete it from the vault manually.';
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    // Let the outcome row linger ~4s (same rule as the video vault's restore
    // and the import card), then clear so the pill disappears. Starting
    // another restore cancels this timer first.
    if (_restoreSession.isActive && !_restoreSession.isWorking) {
      _restoreLingerTimer = Timer(const Duration(seconds: 4), () {
        if (!_restoreSession.isWorking) _restoreSession.clear();
      });
    }
    if (outcome == DocumentRestoreOutcome.restored ||
        outcome == DocumentRestoreOutcome.restoredButVaultCopyRemains) {
      await _loadDocuments();
    }
  }

  /// The hold-a-file action sheet. Photos and videos both answer a long-press
  /// with a sheet of actions, so documents do the same instead of hiding
  /// restore behind the ⋮ menu — the app owner's own report ("should the
  /// document vault also have the restore button?") was proof that the ⋮ menu
  /// alone does not read as "restore lives here" (NN/g #4, consistency: the
  /// same-looking rows in the three vaults must offer their actions the same
  /// way). The ⋮ menu keeps working; this is the same three handlers.
  Future<void> _showDocumentOptions(DocumentMeta doc) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
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
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.unarchive, color: VaultColors.accent),
                ),
                title: const Text('Restore to Device',
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _restoreDocument(doc);
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
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.ios_share, color: VaultColors.accent),
                ),
                title: const Text('Share / export',
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _shareDocument(doc);
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
                  decoration: BoxDecoration(
                    color: VaultColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.drive_file_move_outlined,
                      color: VaultColors.accent),
                ),
                title: const Text('Move to Folder',
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showMoveToFolder(doc);
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
      String? content;
      try {
        content = await ref.read(documentVaultServiceProvider).getTextNote(doc.id);
      } on SystemKeyMissingException catch (_) {
        if (!mounted) return;
        showSecureKeyLostSnackBar(context);
      }
      if (content != null && mounted) {
        final noteContent = content;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DocumentEditorScreen(
              documentId: doc.id,
              initialContent: noteContent,
              isNew: false,
            ),
          ),
        );
        await _loadDocuments();
      }
    } else if (doc.fileType == 'pdf') {
      File? tempFile;
      try {
        tempFile = await ref.read(documentVaultServiceProvider).getDocumentToTempFile(doc.id);
      } on SystemKeyMissingException catch (_) {
        if (!mounted) return;
        showSecureKeyLostSnackBar(context);
      }
      if (tempFile != null && mounted) {
        final pdfFile = tempFile;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(file: pdfFile, title: doc.fileName),
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
    final crypto = ref.watch(vaultCryptoProvider);
    if (!crypto.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route == null || !route.isCurrent) return;
        Navigator.of(context).pushReplacementNamed('/vault-pin');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return VaultScaffold(
      title: 'Documents',
      floatingActionButton: Column(
        // Restore pill above the Add FAB — the same cluster arrangement the
        // video vault uses, so an in-flight restore is visible the same way in
        // both vaults (F26).
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ImportActivityButton(
            key: const ValueKey('restore_activity_button'),
            session: _restoreSession,
            onTap: () => showImportDetailsSheet(context, _restoreSession),
          ),
          const SizedBox(height: 12),
          AnimatedFAB(
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
        ],
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
                          // Same hold-a-file model as photos and videos; the
                          // sheet exposes restore without hunting the ⋮ menu.
                          onLongPress: () => _showDocumentOptions(doc),
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
                                  if (v == 'share') _shareDocument(doc);
                                  if (v == 'move') _showMoveToFolder(doc);
                                  if (v == 'restore') _restoreDocument(doc);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'share', child: Text('Share / export')),
                                  PopupMenuItem(value: 'restore', child: Text('Restore to device…')),
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Text Note',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
            fontFamily: 'Inter',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF3A2DB0), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: _hasChanges
          ? AnimatedFAB(
              child: FloatingActionButton(
                onPressed: _save,
                backgroundColor: const Color(0xFF3A2DB0),
                child: const Icon(Icons.save, color: Colors.white),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _controller,
          cursorColor: const Color(0xFF3A2DB0),
          maxLines: null,
          expands: true,
          decoration: const InputDecoration(
            hintText: 'Start typing...',
            hintStyle: TextStyle(color: Color(0xFF5C5C5C), fontFamily: 'Inter'),
            border: InputBorder.none,
            filled: false,
          ),
          style: const TextStyle(
            fontSize: 17,
            color: Color(0xFF111111),
            fontFamily: 'Inter',
            height: 1.6,
            fontWeight: FontWeight.w600,
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
      final f = widget.file;
      AutoLock.secureDeleteFile(f);
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