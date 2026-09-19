// Shared crypto exception types so VaultCrypto and the background crypto worker can share them without importing each other.

class CorruptedMediaFileException implements Exception {
  final String message;
  const CorruptedMediaFileException([this.message = 'The file is damaged or not in a supported format.']);

  @override
  String toString() => message;
}

/// Typed exception thrown when a media format is not supported by the isolate worker.
class UnsupportedMediaFormatException implements Exception {
  final String message;
  const UnsupportedMediaFormatException([this.message = 'Unsupported media format']);

  @override
  String toString() => message;
}

/// Typed signal that the user cancelled a long-running crypto operation (the
/// import/restore pill's Cancel). Deliberately distinct from a failure so the
/// screens can route it to the honest 'Cancelled' row state instead of
/// 'Failed' — a cancel means nothing went wrong and nothing was lost.
class OperationCancelledException implements Exception {
  final String message;
  const OperationCancelledException([this.message = 'Operation cancelled']);

  @override
  String toString() => message;
}
