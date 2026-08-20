import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../crypto/media_format.dart';

/// A loopback HTTP server that serves decrypted media bytes from CTR-encrypted
/// vault blobs. Designed for use with VideoPlayerController.networkUrl for
/// seekable streaming playback.
///
/// Security: binds ONLY to 127.0.0.1, requires a per-session random token,
/// rejects path traversal, and serves only /media/<id>.
class LocalStreamingServer {
  /// Resolves a vault blob ID to its [File] path.
  final Future<File> Function(String id) resolveVaultFile;

  /// Decrypts a range of plaintext bytes from an encrypted blob file.
  final Future<Uint8List> Function(File src, int offset, int length) decryptRange;

  HttpServer? _server;
  String? _token;
  int? _port;

  static const int _ctrHeaderSize = 24; // 8 magic + 16 IV
  static const int _subChunkSize = 1024 * 1024; // 1 MB

  LocalStreamingServer({
    required this.resolveVaultFile,
    required this.decryptRange,
  });

  /// The port the server is listening on, or null if not started.
  int? get port => _port;

  /// The session token required for all requests, or null if not started.
  String? get token => _token;

  /// Starts the server on loopback, port 0 (OS-assigned). Idempotent.
  Future<void> start() async {
    if (_server != null) return;

    // Generate a cryptographically secure session token (>=32 bytes)
    final random = Random.secure();
    final tokenBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      tokenBytes[i] = random.nextInt(256);
    }
    _token = base64Url.encode(tokenBytes);

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleRequest, onError: (_) {});
  }

  /// Stops the server and clears the session token.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _token = null;
    _port = null;
  }

  /// Constant-time string comparison to prevent timing attacks on the token.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final method = request.method;

      // Only serve /media/<id>
      if (!path.startsWith('/media/')) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      final id = path.substring('/media/'.length);

      String decodedId;
      try {
        decodedId = Uri.decodeComponent(id);
      } catch (_) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }

      // Path safety: reject IDs with path separators or traversal
      if (decodedId.isEmpty ||
          decodedId.contains('/') ||
          decodedId.contains('\\') ||
          decodedId.contains('..')) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }

      // Auth: require valid session token (constant-time comparison)
      final queryToken = request.uri.queryParameters['token'];
      if (queryToken == null || !_constantTimeEquals(queryToken, _token!)) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }

      // Only GET and HEAD are supported
      if (method != 'GET' && method != 'HEAD') {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }

      // Resolve file
      final file = await resolveVaultFile(decodedId);
      if (!await file.exists()) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      // Read magic to verify CTR format
      final fileLength = await file.length();
      bool isCtr = false;
      if (fileLength >= 8) {
        final raf = await file.open(mode: FileMode.read);
        try {
          final magic = Uint8List(8);
          await raf.readInto(magic);
          bool isC1 = true;
          bool isC2 = true;
          for (int i = 0; i < 8; i++) {
            if (magic[i] != kMediaMagicCtrV1[i]) isC1 = false;
            if (magic[i] != kMediaMagicCtrV2[i]) isC2 = false;
          }
          isCtr = isC1 || isC2;
        } finally {
          await raf.close();
        }
      }

      if (!isCtr) {
        request.response.statusCode = 500;
        request.response.write('Blob not CTR-encrypted; migration required');
        await request.response.close();
        return;
      }

      final plaintextLength = fileLength - _ctrHeaderSize;
      final response = request.response;

      // Parse Range header
      final rangeHeader = request.headers.value('range');

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        // --- 206 Partial Content ---
        final rangeSpec = rangeHeader.substring('bytes='.length);
        final dashIndex = rangeSpec.indexOf('-');
        if (dashIndex < 0) {
          response.statusCode = 400;
          await response.close();
          return;
        }

        final startStr = rangeSpec.substring(0, dashIndex);
        final endStr = rangeSpec.substring(dashIndex + 1);

        int start;
        int end;
        try {
          start = int.parse(startStr);
          end = endStr.isEmpty ? plaintextLength - 1 : int.parse(endStr);
        } catch (_) {
          response.statusCode = 400;
          await response.close();
          return;
        }

        if (end >= plaintextLength) end = plaintextLength - 1;

        if (start < 0 || start > end || start >= plaintextLength) {
          response.statusCode = 416;
          response.headers.set('Content-Range', 'bytes */$plaintextLength');
          await response.close();
          return;
        }

        final contentLength = end - start + 1;

        response.statusCode = 206;
        response.headers.set('Accept-Ranges', 'bytes');
        response.headers.set(
            'Content-Range', 'bytes $start-$end/$plaintextLength');
        response.headers.contentType = ContentType('video', 'mp4');
        response.contentLength = contentLength;

        if (method == 'GET') {
          await _streamRange(file, response, start, contentLength);
        }
        await response.close();
      } else {
        // --- 200 Full Content ---
        response.statusCode = 200;
        response.headers.set('Accept-Ranges', 'bytes');
        response.headers.contentType = ContentType('video', 'mp4');
        response.contentLength = plaintextLength;

        if (method == 'GET') {
          await _streamRange(file, response, 0, plaintextLength);
        }
        await response.close();
      }
    } catch (e) {
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Streams decrypted bytes to the response in bounded sub-chunks to keep
  /// memory flat. Never allocates the whole range at once.
  Future<void> _streamRange(
      File file, HttpResponse response, int start, int totalLength) async {
    int remaining = totalLength;
    int currentOffset = start;
    while (remaining > 0) {
      final chunkSize = remaining < _subChunkSize ? remaining : _subChunkSize;
      final chunk = await decryptRange(file, currentOffset, chunkSize);
      response.add(chunk);
      currentOffset += chunkSize;
      remaining -= chunkSize;
    }
  }
}
