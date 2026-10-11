// mimic/lib/vault/screens/storage_optimizer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../services/pro_status_service.dart';
import '../services/storage_optimizer_service.dart';
import '../widgets/paywall_sheet.dart';

class StorageOptimizerScreen extends ConsumerStatefulWidget {
  const StorageOptimizerScreen({super.key});

  @override
  ConsumerState<StorageOptimizerScreen> createState() => _StorageOptimizerScreenState();
}

class _StorageOptimizerScreenState extends ConsumerState<StorageOptimizerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StorageOptimizationReport? _report;
  bool _isLoading = true;
  final Set<String> _selectedFileIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAnalysis();
    });
  }

  Future<void> _loadAnalysis() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(storageOptimizerServiceProvider);
      final res = await service.analyzeVault();
      if (mounted) {
        setState(() {
          _report = res;
          _selectedFileIds.clear();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<OptimizableFile> _getSelectedFiles(StorageOptimizationReport report) {
    return report.allDuplicateCopies
        .where((f) => _selectedFileIds.contains(f.id))
        .toList();
  }

  int _getSelectedBytes(StorageOptimizationReport report) {
    return _getSelectedFiles(report)
        .fold<int>(0, (sum, f) => sum + f.sizeBytes);
  }

  void _selectAllDuplicates(StorageOptimizationReport report) {
    setState(() {
      _selectedFileIds.addAll(report.allDuplicateCopies.map((f) => f.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedFileIds.clear();
    });
  }

  void _toggleGroupSelection(DuplicateGroup group) {
    final copyIds = group.duplicateCopies.map((f) => f.id).toSet();
    final isFullySelected = copyIds.every(_selectedFileIds.contains);
    setState(() {
      if (isFullySelected) {
        _selectedFileIds.removeAll(copyIds);
      } else {
        _selectedFileIds.addAll(copyIds);
      }
    });
  }

  bool _isGroupFullySelected(DuplicateGroup group) {
    if (group.duplicateCopies.isEmpty) return false;
    return group.duplicateCopies.every((f) => _selectedFileIds.contains(f.id));
  }

  Future<void> _confirmDelete(OptimizableFile file) async {
    final isPro = ref.read(isProProvider).valueOrNull ?? false;
    if (!isPro) {
      showPaywallSheet(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete File?'),
        content: Text('Are you sure you want to permanently delete "${file.name}" (${file.formattedSize})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: VaultColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(storageOptimizerServiceProvider).deleteOptimizableFile(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${file.name}'),
            backgroundColor: VaultColors.success,
          ),
        );
      }
      _loadAnalysis();
    }
  }

  Future<void> _confirmDeleteBatch(
    List<OptimizableFile> files, {
    required String title,
    required String description,
  }) async {
    final isPro = ref.read(isProProvider).valueOrNull ?? false;
    if (!isPro) {
      showPaywallSheet(context);
      return;
    }

    if (files.isEmpty) return;

    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    final formattedSize = _report?.formatBytes(totalBytes) ?? '${files.length} files';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_outlined, color: VaultColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VaultColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VaultColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: VaultColors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Original files are kept safe. Frees $formattedSize of storage.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: VaultColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete ${files.length} Copies'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      final count = await ref
          .read(storageOptimizerServiceProvider)
          .deleteOptimizableFiles(files);
      if (mounted) {
        setState(() {
          _selectedFileIds.removeAll(files.map((f) => f.id));
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $count duplicate copies ($formattedSize freed)'),
            backgroundColor: VaultColors.success,
          ),
        );
        _loadAnalysis();
      }
    }
  }

  Future<void> _confirmCleanAllDuplicates(StorageOptimizationReport report) async {
    final allCopies = report.allDuplicateCopies;
    await _confirmDeleteBatch(
      allCopies,
      title: 'Clean All Duplicates?',
      description:
          'Are you sure you want to delete all ${allCopies.length} redundant duplicate copies? Original copies of every file will be kept safe.',
    );
  }

  Future<void> _confirmDeleteSelected(StorageOptimizationReport report) async {
    final selectedFiles = _getSelectedFiles(report);
    await _confirmDeleteBatch(
      selectedFiles,
      title: 'Delete Selected Duplicates?',
      description:
          'Are you sure you want to delete the ${selectedFiles.length} selected duplicate copies? Original copies will remain untouched.',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: const Text(
          'Storage Optimizer',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: VaultColors.accent),
            tooltip: 'Rescan Vault',
            onPressed: _loadAnalysis,
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VaultColors.accent))
          : _report == null
              ? const Center(child: Text('Unable to analyze storage'))
              : Column(
                  children: [
                    if (!isPro) _buildProBanner(),
                    _buildStorageHeader(_report!),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: VaultColors.accent,
                      labelColor: VaultColors.accent,
                      unselectedLabelColor: VaultColors.textSecondary,
                      tabs: [
                        Tab(
                          text: 'Duplicates (${_report!.duplicateGroups.length})',
                          icon: const Icon(Icons.copy_outlined, size: 20),
                        ),
                        Tab(
                          text: 'Large Files (${_report!.largeFiles.length})',
                          icon: const Icon(Icons.video_library_outlined, size: 20),
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDuplicatesTab(_report!),
                          _buildLargeFilesTab(_report!),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF4D8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2C969)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: Color(0xFF947600), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Mimic Pro Feature',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF5A4800),
                  ),
                ),
                Text(
                  '1-tap removal of duplicates and large file management requires Pro.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF7A6200)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showPaywallSheet(context),
            child: const Text('Upgrade', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageHeader(StorageOptimizationReport report) {
    final total = report.totalBytes == 0 ? 1 : report.totalBytes;
    final photoRatio = report.photosBytes / total;
    final videoRatio = report.videosBytes / total;
    final docRatio = report.docsBytes / total;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vault Storage Used',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              Text(
                report.formatBytes(report.totalBytes),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: VaultColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Storage Breakdown Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  if (photoRatio > 0)
                    Expanded(
                      flex: (photoRatio * 100).toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFF6750A4)),
                    ),
                  if (videoRatio > 0)
                    Expanded(
                      flex: (videoRatio * 100).toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFF1976D2)),
                    ),
                  if (docRatio > 0)
                    Expanded(
                      flex: (docRatio * 100).toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFF006874)),
                    ),
                  if (report.totalBytes == 0)
                    Expanded(
                      child: Container(color: Colors.grey.shade300),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegend(
                color: const Color(0xFF6750A4),
                label: 'Photos',
                size: report.formatBytes(report.photosBytes),
              ),
              _buildLegend(
                color: const Color(0xFF1976D2),
                label: 'Videos',
                size: report.formatBytes(report.videosBytes),
              ),
              _buildLegend(
                color: const Color(0xFF006874),
                label: 'Docs',
                size: report.formatBytes(report.docsBytes),
              ),
            ],
          ),
          if (report.potentialDuplicateSavings > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: VaultColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cleaning_services_outlined, color: VaultColors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Potential savings: ${report.formatBytes(report.potentialDuplicateSavings)} in duplicate files',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: VaultColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend({required Color color, required String label, required String size}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: VaultColors.textSecondary)),
            Text(size, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VaultColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildDuplicatesTab(StorageOptimizationReport report) {
    if (report.duplicateGroups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: VaultColors.success, size: 48),
              SizedBox(height: 12),
              Text(
                'No Duplicate Files Found',
                style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'All media items in your vault are unique.',
                style: TextStyle(color: VaultColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final totalDuplicates = report.allDuplicateCopies.length;
    final allSelected = totalDuplicates > 0 && _selectedFileIds.length >= totalDuplicates;
    final someSelected = _selectedFileIds.isNotEmpty;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, someSelected ? 90 : 16),
          children: [
            // 1. One-Tap Clean All Banner
            _buildCleanAllBanner(report),
            const SizedBox(height: 12),

            // 2. Multi-Select Toolbar
            _buildSelectionToolbar(report, allSelected, totalDuplicates),
            const SizedBox(height: 12),

            // 3. Duplicate Groups Cards
            ...report.duplicateGroups.map((group) => _buildDuplicateGroupCard(report, group)),
          ],
        ),

        // 4. Floating / Sticky Bottom Action Bar
        if (someSelected)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildBottomDeleteBar(report),
          ),
      ],
    );
  }

  Widget _buildCleanAllBanner(StorageOptimizationReport report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            VaultColors.accent.withValues(alpha: 0.12),
            VaultColors.accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VaultColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VaultColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_delete_outlined, color: VaultColors.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clean All Duplicates',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: VaultColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${report.allDuplicateCopies.length} redundant copies (Saves ${report.formatBytes(report.potentialDuplicateSavings)})',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: VaultColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _confirmCleanAllDuplicates(report),
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: const Text('Clean All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(
    StorageOptimizationReport report,
    bool allSelected,
    int totalDuplicates,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (allSelected) {
                _deselectAll();
              } else {
                _selectAllDuplicates(report);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    activeColor: VaultColors.accent,
                    onChanged: (val) {
                      if (val == true) {
                        _selectAllDuplicates(report);
                      } else {
                        _deselectAll();
                      }
                    },
                  ),
                  Text(
                    allSelected ? 'Deselect All' : 'Select All ($totalDuplicates)',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: VaultColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (_selectedFileIds.isNotEmpty) ...[
            Text(
              '${_selectedFileIds.length} selected',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: VaultColors.accent,
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: _deselectAll,
              child: const Text('Clear', style: TextStyle(fontSize: 12, color: VaultColors.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuplicateGroupCard(StorageOptimizationReport report, DuplicateGroup group) {
    final isGroupSelected = _isGroupFullySelected(group);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: VaultColors.surface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.files.first.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.files.length} copies • ${report.formatBytes(group.potentialSavings)} savable',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: VaultColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _toggleGroupSelection(group),
                  icon: Icon(
                    isGroupSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: VaultColors.accent,
                  ),
                  label: Text(
                    isGroupSelected ? 'Deselect Group' : 'Select Group',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: VaultColors.accent),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...group.files.asMap().entries.map((entry) {
              final fileIdx = entry.key;
              final file = entry.value;
              final isOriginal = fileIdx == 0;
              final isSelected = _selectedFileIds.contains(file.id);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOriginal
                        ? VaultColors.success.withValues(alpha: 0.6)
                        : isSelected
                            ? VaultColors.accent.withValues(alpha: 0.6)
                            : Colors.grey.shade300,
                    width: (isOriginal || isSelected) ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    if (isOriginal)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: VaultColors.success.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified, color: VaultColors.success, size: 18),
                      )
                    else
                      Checkbox(
                        value: isSelected,
                        activeColor: VaultColors.accent,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedFileIds.add(file.id);
                            } else {
                              _selectedFileIds.remove(file.id);
                            }
                          });
                        },
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isOriginal ? 'Original Copy' : 'Duplicate #$fileIdx',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: isOriginal ? FontWeight.bold : FontWeight.w600,
                                  color: isOriginal ? VaultColors.success : VaultColors.textPrimary,
                                ),
                              ),
                              if (isOriginal) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: VaultColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline, size: 10, color: VaultColors.success),
                                      SizedBox(width: 3),
                                      Text(
                                        'PROTECTED',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: VaultColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            file.formattedSize,
                            style: const TextStyle(fontSize: 11, color: VaultColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (!isOriginal)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: VaultColors.error, size: 20),
                        tooltip: 'Delete Duplicate',
                        onPressed: () => _confirmDelete(file),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomDeleteBar(StorageOptimizationReport report) {
    final selectedCount = _selectedFileIds.length;
    final selectedBytes = _getSelectedBytes(report);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: VaultColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$selectedCount copies selected',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: VaultColors.textPrimary,
                  ),
                ),
                Text(
                  'Frees ${report.formatBytes(selectedBytes)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: VaultColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _confirmDeleteSelected(report),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Delete Selected', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeFilesTab(StorageOptimizationReport report) {
    if (report.largeFiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: VaultColors.success, size: 48),
              SizedBox(height: 12),
              Text(
                'No Large Files Found',
                style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'No single media item exceeds 20 MB.',
                style: TextStyle(color: VaultColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: report.largeFiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final file = report.largeFiles[idx];
        IconData icon;
        Color color;
        switch (file.type) {
          case VaultMediaType.video:
            icon = Icons.videocam_outlined;
            color = const Color(0xFF1976D2);
            break;
          case VaultMediaType.photo:
            icon = Icons.photo_outlined;
            color = const Color(0xFF6750A4);
            break;
          case VaultMediaType.document:
            icon = Icons.description_outlined;
            color = const Color(0xFF006874);
            break;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: VaultColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${file.type.name.toUpperCase()} • ${file.formattedSize}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: file.sizeBytes > 50 * 1024 * 1024 ? VaultColors.error : VaultColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: VaultColors.error),
                tooltip: 'Delete File',
                onPressed: () => _confirmDelete(file),
              ),
            ],
          ),
        );
      },
    );
  }
}
