// lib/vault/widgets/import_activity_button.dart
//
// Compact import-status control (F4 rework, UX review 2026-09-17). The old
// ImportStatusCard floated the whole per-file queue above the grid, which ate
// vertical space during large batches. The NN/g heuristics this keeps:
//  - Visibility of system status: a labelled pill with live counts is always
//    visible while an import runs — the user never has to guess.
//  - Progressive disclosure: per-file detail moves into a bottom sheet the
//    user opens on demand, instead of a permanently expanded card.
//  - Recognition over recall: the pill carries WORDS ("Importing 2/5"), not
//    just a spinner an unfamiliar user must interpret.
// The pill sits directly above the + FAB so both import controls form one
// cluster. Tapping it opens the sheet; dismissing the sheet never stops the
// import — closing a view is not cancelling work.
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../services/import_progress.dart';
import 'import_status_card.dart' show importFileRowIcon, importFileRowColor;

/// The compact, always-visible import status pill. Renders nothing while the
/// session is empty (a settled session lingers ~4s so its outcome stays
/// readable, exactly like the old card did).
class ImportActivityButton extends StatelessWidget {
  final ImportSession session;
  final VoidCallback onTap;

  const ImportActivityButton({
    super.key,
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (!session.isActive) return const SizedBox.shrink();
        final working = session.isWorking;
        final failed =
            session.files.where((f) => f.status == ImportFileStatus.failed).length;
        final String label;
        if (working) {
          label = 'Importing ${session.position}/${session.total}';
        } else if (failed > 0) {
          label = 'Import finished — $failed not imported';
        } else {
          label = 'Import finished (${session.total}/${session.total})';
        }
        return Material(
          color: VaultColors.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              // 44px tall: a comfortable touch target for a secondary control.
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: VaultColors.accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: VaultColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the on-demand detail sheet: one row per file with the same truthful
/// statuses the old card showed. Safe to open at any point of the import; if
/// the session clears while it is open the sheet shows a neutral done line.
Future<void> showImportDetailsSheet(
    BuildContext context, ImportSession session) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: VaultColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          final rows = session.files;
          return SafeArea(
            child: SizedBox(
              // Roughly half the screen: the queue is scannable, the grid
              // stays reachable behind the sheet (modal, so it dims anyway).
              height: MediaQuery.of(sheetContext).size.height * 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      session.isWorking
                          ? 'Importing ${session.position}/${session.total} ...'
                          : 'Import finished',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No active import.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: VaultColors.textSecondary),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          return ListTile(
                            dense: true,
                            leading: importFileRowIcon(row.status),
                            title: Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: VaultColors.textPrimary,
                              ),
                            ),
                            subtitle: row.detail == null
                                ? null
                                : Text(
                                    row.detail!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      color: VaultColors.textTertiary,
                                    ),
                                  ),
                            trailing: Text(
                              importFileStatusLabel(row.status),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: importFileRowColor(row.status),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Close',
                          style: TextStyle(
                              fontFamily: 'Inter', color: VaultColors.accent)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
