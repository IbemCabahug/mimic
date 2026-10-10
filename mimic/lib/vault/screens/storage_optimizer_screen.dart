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
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: report.duplicateGroups.length,
      itemBuilder: (ctx, idx) {
        final group = report.duplicateGroups[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: VaultColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        group.files.first.name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: VaultColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${group.files.length} copies • ${report.formatBytes(group.potentialSavings)} savable',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: VaultColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...group.files.asMap().entries.map((entry) {
                  final fileIdx = entry.key;
                  final file = entry.value;
                  final isOriginal = fileIdx == 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isOriginal ? VaultColors.success : Colors.grey.shade300,
                        width: isOriginal ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOriginal ? Icons.verified : Icons.content_copy,
                          color: isOriginal ? VaultColors.success : VaultColors.textTertiary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOriginal ? 'Keep: Original' : 'Duplicate copy #$fileIdx',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: isOriginal ? FontWeight.bold : FontWeight.normal,
                                  color: isOriginal ? VaultColors.success : VaultColors.textPrimary,
                                ),
                              ),
                              Text(
                                file.formattedSize,
                                style: const TextStyle(fontSize: 11, color: VaultColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (!isOriginal)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: VaultColors.error),
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
      },
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
