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
        final failed = session.files
            .where((f) => f.status == ImportFileStatus.failed)
            .length;
        final needsSourceCount = session.files
            .where((f) => f.status == ImportFileStatus.needsSource)
            .length;
        final issuesCount = failed + needsSourceCount;
        // The active row's measurable percent, when the work is of a kind that
        // HAS one (restore decrypt). Imports have none and simply omit it —
        // the NN/g rule this follows is "percent-done for >=10 s waits", and a
        // percent that cannot be measured must not be invented.
        final activeRow =
            session.position >= 1 && session.position <= session.total
            ? session.files[session.position - 1]
            : null;
        final activePercent = activeRow?.progress;
        // Restore rows that are past their measurable part (gallery write) or
        // still in-flight indeterminately show a plain spinner percent-less
        // label; the sheet carries the phase detail.
        final String label;
        if (working) {
          // A requested cancel is itself a status the user must see: the
          // in-flight file still finishes, so "Cancelling…" is the honest
          // label until the loop actually stops.
          if (session.cancelRequested) {
            label = 'Cancelling…';
          } else {
            final base = '${session.verb} ${session.position}/${session.total}';
            label = activePercent != null
                ? '$base — ${(activePercent * 100).round()}%'
                : base;
          }
        } else if (session.isPaused) {
          label = switch (session.pauseReason) {
            ImportPauseReason.lowStorage => 'Import paused — storage full',
            ImportPauseReason.databaseFailure =>
              'Import paused — database error',
            ImportPauseReason.permissionDenied =>
              'Import paused — grant permission',
            ImportPauseReason.userPaused => 'Import paused',
            ImportPauseReason.serviceTimedOut =>
              'Import paused — time limit reached',
            ImportPauseReason.serviceStopped =>
              'Import paused — background stopped',
            ImportPauseReason.locked => 'Import paused',
            ImportPauseReason.none => 'Import paused',
          };
        } else if (session.cancelRequested) {
          label = session.verb == 'Restoring'
              ? 'Restore cancelled'
              : 'Import cancelled';
        } else if (issuesCount > 0) {
          label = session.verb == 'Restoring'
              ? 'Restore finished — $failed not restored'
              : 'Import finished — $issuesCount not imported';
        } else if (session.hasAwaitingDeleteConfirm) {
          label = 'Saved — confirm original deletion';
        } else {
          label = session.verb == 'Restoring'
              ? 'Restore finished (${session.total}/${session.total})'
              : 'Import finished (${session.total}/${session.total})';
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
                border: Border.all(
                  color: VaultColors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: working
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: VaultColors.accent,
                          )
                        : session.isPaused
                        ? const Icon(
                            Icons.pause_circle_outline,
                            size: 16,
                            color: Colors.orange,
                          )
                        : Icon(
                            issuesCount > 0 || session.hasAwaitingDeleteConfirm
                                ? Icons.error_outline
                                : Icons.check_circle,
                            size: 16,
                            color:
                                issuesCount > 0 ||
                                    session.hasAwaitingDeleteConfirm
                                ? Colors.orange
                                : Colors.green,
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
                  // The ✕ requests the cancel; the loops stop before the NEXT
                  // file, so this never truncates the file in flight. It is
                  // an immediate action with no confirm dialog on purpose:
                  // already-encrypted files simply stay in the vault, so a
                  // cancel costs nothing but the remaining waiting time.
                  if (working) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: session.verb == 'Restoring'
                          ? 'Cancel restore'
                          : 'Cancel import',
                      child: InkWell(
                        onTap: session.requestCancel,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: VaultColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
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
  BuildContext context,
  ImportSession session,
) {
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
                          ? '${session.verb} ${session.position}/${session.total} ...'
                          : session.isPaused
                          ? 'Import paused'
                          : session.verb == 'Restoring'
                          ? 'Restore finished'
                          : 'Import finished',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                  ),
                  if (session.pauseMessage != null &&
                      session.pauseReason != ImportPauseReason.none)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                      child: Text(
                        session.pauseMessage!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  else if (session.isWorking)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
                      child: Text(
                        'Continues when switching apps until locked, paused, or finished. Locking stops active progress and restarts unfinished files on unlock.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: VaultColors.textSecondary,
                        ),
                      ),
                    ),
                  if (session.backgroundServiceWarning != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        session.backgroundServiceWarning!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.orange,
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
                          color: VaultColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          // Determinate restore percent -> the trailing text
                          // becomes the percent and a bar appears under the
                          // name; indeterminate restore -> plain 'Restoring'
                          // plus a moving bar with no fake percent.
                          final showRestorePercent =
                              row.status == ImportFileStatus.restoring &&
                              row.progress != null;
                          final showImportPercent =
                              (row.status == ImportFileStatus.preparing ||
                                  row.status == ImportFileStatus.encrypting) &&
                              row.progress != null;
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
                            subtitle:
                                (row.detail == null &&
                                    row.status != ImportFileStatus.restoring)
                                ? null
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (row.detail != null)
                                        Text(
                                          row.detail!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            color: VaultColors.textTertiary,
                                          ),
                                        ),
                                      if (row.status ==
                                              ImportFileStatus.restoring ||
                                          showImportPercent)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          // A null value IS the indeterminate
                                          // bar: when the OS-side gallery write
                                          // has no observable percent the bar
                                          // moves without claiming a number
                                          // (never fake progress). With a value
                                          // it is the streamed decrypt's real
                                          // percent.
                                          child: LinearProgressIndicator(
                                            minHeight: 3,
                                            value: row.progress,
                                            color: VaultColors.accent,
                                            backgroundColor: VaultColors.accent
                                                .withValues(alpha: 0.15),
                                          ),
                                        ),
                                    ],
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  showRestorePercent
                                      ? '${(row.progress! * 100).round()}%'
                                      : showImportPercent
                                      ? '${importFileStatusLabel(row.status)} ${(row.progress! * 100).round()}%'
                                      : importFileStatusLabel(row.status),
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: importFileRowColor(row.status),
                                  ),
                                ),
                                if (session.onRetryItem != null &&
                                    (row.status == ImportFileStatus.failed ||
                                        row.status ==
                                            ImportFileStatus.needsSource ||
                                        row.status ==
                                            ImportFileStatus.pausedLocked))
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    color: VaultColors.accent,
                                    tooltip: 'Retry item',
                                    onPressed: () => session.onRetryItem!(i),
                                  ),
                                if (session.onCancelItem != null &&
                                    (row.status == ImportFileStatus.queued ||
                                        row.status ==
                                            ImportFileStatus.pausedLocked ||
                                        row.status ==
                                            ImportFileStatus.needsSource))
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    color: VaultColors.textTertiary,
                                    tooltip: 'Cancel item',
                                    onPressed: () => session.onCancelItem!(i),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      children: [
                        if (session.hasAwaitingDeleteConfirm &&
                            session.onConfirmPendingDeletes != null)
                          TextButton(
                            onPressed: () => session.onConfirmPendingDeletes!(),
                            child: const Text(
                              'Confirm Delete Originals',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        if (session.hasRetryableWork &&
                            session.onRetryAll != null)
                          TextButton(
                            onPressed: session.onRetryAll,
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: VaultColors.accent,
                              ),
                            ),
                          ),
                        if (session.hasClearableItems &&
                            session.onClearFinished != null)
                          TextButton(
                            onPressed: session.onClearFinished,
                            child: const Text(
                              'Clear finished',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: VaultColors.textSecondary,
                              ),
                            ),
                          ),
                        // Same rule as the pill's ✕: closing a view is not
                        // cancelling work, so the sheet's Cancel is a separate
                        // explicit control and only exists while work is live.
                        if (session.isWorking)
                          TextButton(
                            onPressed: session.requestCancel,
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: VaultColors.textTertiary,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: VaultColors.accent,
                            ),
                          ),
                        ),
                      ],
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
