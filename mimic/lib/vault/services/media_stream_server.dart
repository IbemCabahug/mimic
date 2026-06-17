// lib/vault/services/media_stream_server.dart
import 'dart:io';
import 'dart:typed_data';

import 'local_streaming_server.dart';
import 'video_vault_service.dart';

class MediaStreamServer {
  static final MediaStreamServer instance = MediaStreamServer._internal();
  MediaStreamServer._internal();

  VideoVaultService? _videoVaultService;
  Future<File> Function(String id)? _resolveVaultFile;
  Future<Uint8List> Function(File file, int offset, int length)? _decryptRange;

  LocalStreamingServer? _server;

  /// Initializes the server dependencies. Idempotent.
  void init({
    required VideoVaultService videoVaultService,
    required Future<File> Function(String id) resolveVaultFile,
    required Future<Uint8List> Function(File file, int offset, int length) decryptRange,
  }) {
    _videoVaultService = videoVaultService;
    _resolveVaultFile = resolveVaultFile;
    _decryptRange = decryptRange;
  }

  /// Returns the streamable loopback URL for the given video ID.
  /// Starts the server lazily if not already running.
  Future<Uri> urlFor(String id) async {
    if (_videoVaultService == null || _resolveVaultFile == null || _decryptRange == null) {
      throw StateError('MediaStreamServer is not initialized. Call init() first.');
    }

    // First ensure the video is streamable (migrated to CTR if needed)
    await _videoVaultService!.ensureVideoStreamable(id);

    if (_server == null) {
      _server = LocalStreamingServer(
        resolveVaultFile: _resolveVaultFile!,
        decryptRange: _decryptRange!,
      );
      await _server!.start();
    }

    return Uri.parse(
      'http://127.0.0.1:${_server!.port}/media/$id?token=${_server!.token}',
    );
  }

  /// Stops the underlying server and clears references.
  /// Clears token/server references synchronously first, then closes the underlying server.
  Future<void> stop() async {
    final serverToStop = _server;
    _server = null; // Cleared synchronously first
    if (serverToStop != null) {
      await serverToStop.stop();
    }
  }

  /// Resets all dependencies and fields to null. Internal use for testing.
  void reset() {
    _videoVaultService = null;
    _resolveVaultFile = null;
    _decryptRange = null;
    _server = null;
  }
}
