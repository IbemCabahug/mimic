// lib/vault/services/import_progress.dart
//
// Import-session state for the gallery import flows (video/photo). The user
// report: a 2:34 video encrypts for a long while with NO frontend sign — the
// screen looks dead until the system "Allow mimic to delete this video?"
// dialog appears. So each screen now owns one ImportSession (a ChangeNotifier)
// and renders a live status card above the grid while it is non-empty:
// one row per chosen file (Queued -> Encrypting N/M -> Waiting for delete
// confirmation -> Saved / Saved, original kept / Failed).
//
// The delete-confirmation wait is one state, not two: the OS shows its dialog
// and runs the delete inside the same call, so there is no boundary to report
// between "deciding" and "deleting". Row outcomes are truthful because the
// services now return `originalsKept` — a denied dialog leaves the source on
// the device, and the row must not claim a clean 'Saved' when that happens.
//
// Words follow future_feature.md F-import-progress: Importing/Encrypting/
// Saved/Failed — never "upload", which would imply the bytes leave the
// device. Statuses stream via notifyListeners; tests drive the pure model
// without any widget/plugin chain.
import 'package:flutter/foundation.dart';

enum ImportFileStatus {
  queued,
  encrypting,
  waitingDeleteConfirm,
  saved,
  savedOriginalKept,
  failed,
}

String importFileStatusLabel(ImportFileStatus status) {
  switch (status) {
    case ImportFileStatus.queued:
      return 'Queued';
    case ImportFileStatus.encrypting:
      return 'Encrypting';
    // Covers the whole OS delete-confirmation phase (dialog up, user deciding,
    // and the delete pass the OS runs after "Allow"). There is no observable
    // boundary between those, so one honest label covers them all.
    case ImportFileStatus.waitingDeleteConfirm:
      return 'Waiting for delete confirmation';
    case ImportFileStatus.saved:
      return 'Saved';
    case ImportFileStatus.savedOriginalKept:
      return 'Saved, original kept';
    case ImportFileStatus.failed:
      return 'Failed';
  }
}

class ImportFileEntry {
  String name;
  ImportFileStatus status;
  String? detail;
  ImportFileEntry({required this.name, this.status = ImportFileStatus.queued, this.detail});
}

/// One import session: the ordered file list plus a 1-based position cursor.
/// The owning screen creates it when the picker returns and clears it after
/// the flow settles (saved/failed rows linger briefly so the user sees the
/// outcome). Synchronous and widget-free so unit tests can drive it.
class ImportSession extends ChangeNotifier {
  final List<ImportFileEntry> files = [];
  int position = 0;
  int get total => files.length;

  bool get isActive => files.isNotEmpty;
  bool get isWorking => files.any((f) =>
      f.status == ImportFileStatus.queued ||
      f.status == ImportFileStatus.encrypting ||
      f.status == ImportFileStatus.waitingDeleteConfirm);

  void begin(List<String> names) {
    files.clear();
    files.addAll(names.map((n) => ImportFileEntry(name: n)));
    position = names.isEmpty ? 0 : 1;
    notifyListeners();
  }

  /// Pre-creates one row per chosen item the moment the picker reports the
  /// batch size, so the header can read "Importing 1/5 ..." and the user sees
  /// the whole queue ('Queued' rows) instead of a count that grows per file.
  /// Names arrive later, per file, via [ensureSlot].
  void setTotal(int total) {
    while (files.length < total) {
      files.add(ImportFileEntry(name: '...'));
    }
    if (files.length > total) files.removeRange(total, files.length);
    if (position == 0 && total > 0) position = 1;
    notifyListeners();
  }

  /// Grows the file list to fit [index], naming the new slot [name]. The
  /// screen calls this from onFileStart because it learns file names one at
  /// a time (the picker result lives inside the service).
  void ensureSlot(int index, String name) {
    while (files.length <= index) {
      files.add(ImportFileEntry(name: name));
    }
    files[index].name = name;
    notifyListeners();
  }

  void _set(int index, ImportFileStatus status, {String? detail}) {
    if (index < 0 || index >= files.length) return;
    files[index].status = status;
    files[index].detail = detail;
    notifyListeners();
  }

  void markEncrypting(int index, int positionOneBased) {
    position = positionOneBased;
    _set(index, ImportFileStatus.encrypting);
  }

  /// The OS delete-confirmation dialog is now up. It stays up while the user
  /// decides, and the OS then runs the delete inside the same call, so
  /// encrypting rows move here and stay here for that whole phase.
  void markWaitingDeleteConfirm() {
    for (var i = 0; i < files.length; i++) {
      if (files[i].status == ImportFileStatus.encrypting) {
        files[i].status = ImportFileStatus.waitingDeleteConfirm;
      }
    }
    notifyListeners();
  }

  void markSaved(int index) => _set(index, ImportFileStatus.saved);
  void markSavedOriginalKept(int index) => _set(index, ImportFileStatus.savedOriginalKept);
  void markFailed(int index, [String? detail]) => _set(index, ImportFileStatus.failed, detail: detail);

  void clear() {
    files.clear();
    position = 0;
    notifyListeners();
  }
}
