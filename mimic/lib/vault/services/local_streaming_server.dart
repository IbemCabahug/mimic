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

  /// Set by [stop] before anything is awaited, so an in-flight [_streamRange]
  /// sees it on its next sub-chunk. This is H15: the bytes a popped player
  /// abandoned must not keep being decrypted on the UI isolate.
  ///
  /// Before this flag the loop had NO cancellation check at all (pre-3G-1C code
  /// at HEAD: `while (remaining > 0) { ... response.add(chunk); }`) and `stop()`
  /// only closed the socket, so nothing in the code could stop a range that was
  /// already being served — it ran to the end of the requested range. Measured
  /// against that pre-fix code on 2026-09-16: with the loop at decrypt call 11
  /// of 32, `stop()` returned in 15 ms and the loop still reached 32; with the
  /// client gone at call 12 it also still reached 32 (worksheet section 13).
  bool _cancelled = false;

  static const int _ctrHeaderSize = 24; // 8 magic + 16 IV
  // M13 residual: per-range decrypt runs inline on the UI isolate, so one
  // range holds the event loop for its whole AES pass. 256 KB is 4x less
  // uninterrupted work per chunk than the 1 MB it replaced, at the same
  // measured throughput (~27 MB/s at both sizes, desktop, 2026-09-16); memory
  // stays flat because only one chunk is live.
  static const int _subChunkSize = 256 * 1024; // 256 KB

  LocalStreamingServer({
    required this.resolveVaultFile,
    required this.decryptRange,
  });

  /// The port the server is listening on, or null if not started.
  int? get port => _port;

  /// The session token required for all requests, or null if not started.
  String? get token => _token;

  /// Starts the server on loopback, port 0 (OS-assigned). Idempotent.
  ///
  /// A restart after [stop] clears the abort flag. The flag belongs to the
  /// session that was stopped, and leaving it set would make the new session
  /// answer every range with a 206 and an empty body — the H15 guard would
  /// then be indistinguishable from a broken server.
  Future<void> start() async {
    if (_server != null) return;

    _cancelled = false;

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

  /// Stops the server, clears the session token, and aborts any in-flight range
  /// decrypt. The abort flag is set synchronously, before the first await, so a
  /// loop that is already mid-range cannot miss it (H15).
  ///
  /// A later play builds a NEW server instance with the flag clear, so aborting
  /// one session never affects the next.
  Future<void> stop() async {
    _cancelled = true;
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
          // C10: accept c2 ONLY. Legacy c1 blobs are keyed by the device-local
          // system key, which stays readable while the vault is locked, so
          // serving a c1 blob here would leak plaintext from a locked vault.
          // A c1 blob falls through to the non-CTR rejection below.
          bool isC2 = true;
          for (int i = 0; i < 8; i++) {
            if (magic[i] != kMediaMagicCtrV2[i]) isC2 = false;
          }
          isCtr = isC2;
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
  /// memory flat. Never allocates the whole range at once. Each await yields
  /// to the UI event loop (M13), so playback start competes less with the
  /// interface thread even though the AES itself stays inline by decision.
  ///
  /// H15: this loop exits as soon as the session is cancelled or the client
  /// stops accepting bytes. A player asks for an OPEN-ENDED range, so without
  /// those two exits a popped player leaves the whole remainder of the file
  /// decrypting inline on the UI isolate.
  Future<void> _streamRange(
      File file, HttpResponse response, int start, int totalLength) async {
    int remaining = totalLength;
    int currentOffset = start;
    while (remaining > 0) {
      if (_cancelled) return; // stop() landed: the reader is gone
      final chunkSize = remaining < _subChunkSize ? remaining : _subChunkSize;
      final chunk = await decryptRange(file, currentOffset, chunkSize);
      if (_cancelled) return; // stop() landed during that decrypt
      try {
        response.add(chunk);
        // Flush the socket chunk before decrypting the next one: the player can
        // start on the first bytes while the rest still decrypts.
        await response.flush();
      } catch (_) {
        // The client went away (player popped) or the response is closed.
        // Decrypting further would burn the UI isolate for nobody.
        return;
      }
      currentOffset += chunkSize;
      remaining -= chunkSize;
    }
  }
}
