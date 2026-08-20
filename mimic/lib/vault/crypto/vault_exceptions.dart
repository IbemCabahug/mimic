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
