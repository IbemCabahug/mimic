// lib/vault/widgets/import_status_card.dart
// Live import-status card rendered above the vault grid while an
// ImportSession is active. One row per file with a status icon + label, plus
// a header line ("Importing 2/3 ..."). Pure view over ImportSession — the
// session itself stays widget-free for unit tests.
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../services/import_progress.dart';

class ImportStatusCard extends StatelessWidget {
  final ImportSession session;
  const ImportStatusCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (!session.isActive) return const SizedBox.shrink();
        final working = session.isWorking;
        final failed =
            session.files.where((f) => f.status == ImportFileStatus.failed).length;
        final String headerText;
        if (working) {
          headerText = 'Importing ${session.position}/${session.total} ...';
        } else if (failed > 0) {
          headerText = 'Import finished — $failed not imported';
        } else {
          headerText = 'Import finished (${session.total}/${session.total})';
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: VaultColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VaultColors.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: working
                        ? const CircularProgressIndicator(
                            strokeWidth: 2, color: VaultColors.accent)
                        : Icon(
                            failed > 0 ? Icons.error_outline : Icons.check_circle,
                            size: 16,
                            color: failed > 0 ? Colors.orange : Colors.green,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerText,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // A large batch must not push the grid off screen: rows scroll
              // inside the card.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 132),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < session.files.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              _rowIcon(session.files[i].status),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      session.files[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: VaultColors.textSecondary,
                                      ),
                                    ),
                                    if (session.files[i].detail != null)
                                      Text(
                                        session.files[i].detail!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 10,
                                          color: VaultColors.textTertiary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                importFileStatusLabel(session.files[i].status),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _rowColor(session.files[i].status),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Both of these delegate to the shared top-level helpers below so the card
  // and the compact pill's detail sheet can never drift apart. (They used to
  // be two hand-copied switch statements, and the copy here silently missed
  // the F26 `restoring` status — the shared version is the single source.)
  Widget _rowIcon(ImportFileStatus status) => importFileRowIcon(status);

  Color _rowColor(ImportFileStatus status) => importFileRowColor(status);
}

// Top-level so other import surfaces (the compact activity button's detail
// sheet) render rows identically to the card without owning an instance.
Widget importFileRowIcon(ImportFileStatus status) {
  switch (status) {
    case ImportFileStatus.queued:
      return const Icon(Icons.schedule, size: 14, color: VaultColors.textTertiary);
    case ImportFileStatus.encrypting:
    case ImportFileStatus.restoring:
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: VaultColors.accent),
      );
    case ImportFileStatus.waitingDeleteConfirm:
      return const Icon(Icons.help_outline, size: 14, color: Colors.orange);
    case ImportFileStatus.saved:
      return const Icon(Icons.check_circle, size: 14, color: Colors.green);
    case ImportFileStatus.savedOriginalKept:
      return const Icon(Icons.info_outline, size: 14, color: Colors.orange);
    case ImportFileStatus.failed:
      return const Icon(Icons.error_outline, size: 14, color: Colors.red);
    case ImportFileStatus.cancelled:
      return const Icon(Icons.remove_circle_outline,
          size: 14, color: VaultColors.textTertiary);
  }
}

Color importFileRowColor(ImportFileStatus status) {
  switch (status) {
    case ImportFileStatus.saved:
      return Colors.green;
    case ImportFileStatus.failed:
      return Colors.red;
    case ImportFileStatus.cancelled:
      return VaultColors.textTertiary;
    case ImportFileStatus.savedOriginalKept:
    case ImportFileStatus.waitingDeleteConfirm:
      return Colors.orange;
    case ImportFileStatus.queued:
      return VaultColors.textTertiary;
    case ImportFileStatus.encrypting:
    case ImportFileStatus.restoring:
      return VaultColors.accent;
  }
}
