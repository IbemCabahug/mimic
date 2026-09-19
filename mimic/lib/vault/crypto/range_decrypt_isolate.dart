// lib/vault/crypto/range_decrypt_isolate.dart
// M13 follow-up: per-range AES moves off the UI isolate into a worker.
// Pays Isolate.spawn ONCE per unlock, answers every 256KB chunk by port.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'media_format.dart';
import 'vault_exceptions.dart';

class RangeDecryptWorkerInit {
  final Uint8List masterKey;
  final Uint8List? systemKey;
  final SendPort bootstrapPort;
  final SendPort responsePort;
  RangeDecryptWorkerInit({
    required this.masterKey,
    required this.systemKey,
    required this.bootstrapPort,
    required this.responsePort,
  });
}

void rangeCtrIncrement(Uint8List counter) {
  for (int i = 15; i >= 0; i--) {
    counter[i] = (counter[i] + 1) & 0xFF;
    if (counter[i] != 0) break;
  }
}

Uint8List rangeCtrAt(Uint8List iv, int blockIndex) {
  final counter = Uint8List.fromList(iv);
  int carry = blockIndex;
  for (int i = 15; i >= 0 && carry > 0; i--) {
    final sum = counter[i] + carry;
    counter[i] = sum & 0xFF;
    carry = sum >> 8;
  }
  return counter;
}

/// Decrypts [length] bytes of the CTR payload [encrypted] (already read from
/// [offset] in the file) using the counter block derived from [iv] and
/// [offset]. Shared by the seekable range request and the whole-file request
/// added for photo blobs, so both use one implementation of the CTR math.
Uint8List ctrDecryptRange({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List encrypted,
  required int offset,
  required int length,
}) {
  final aes = AESEngine()..init(true, KeyParameter(key));
  final out = Uint8List(length);
  final startBlock = offset ~/ 16;
  int skip = offset % 16;
  final ksBlock = Uint8List(16);
  int outPos = 0;
  int blockIndex = startBlock;
  while (outPos < length) {
    final counter = rangeCtrAt(iv, blockIndex);
    aes.processBlock(counter, 0, ksBlock, 0);
    for (int i = skip; i < 16 && outPos < length; i++) {
      out[outPos] = encrypted[outPos] ^ ksBlock[i];
      outPos++;
    }
    skip = 0;
    blockIndex++;
  }
  ksBlock.fillRange(0, ksBlock.length, 0);
  return out;
}

/// Decrypts a PKCS7-padded AES-CBC payload, byte-for-byte the same
/// construction VaultCrypto._createCipher builds for the v1 and legacy
/// formats. Bad padding (a wrong key or a damaged blob) is reported as
/// corruption rather than leaking a PointyCastle error to the caller.
Uint8List cbcDecryptPadded({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List encrypted,
}) {
  if (encrypted.isEmpty) return Uint8List(0);
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  cipher.init(
    false,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
  );
  try {
    return cipher.process(encrypted);
  } on ArgumentError {
    // PKCS7 unpadding reports a bad pad block this way. RangeError is
    // deliberately not listed separately: it is a subtype of ArgumentError, so
    // a second clause would be dead code the analyzer flags.
    throw const CorruptedMediaFileException();
  } catch (e) {
    // PointyCastle raises its own InvalidCipherTextException type for a bad
    // pad block; matching by name avoids importing the pointycastle
    // exceptions file into this isolate for one clause.
    if (e is StateError ||
        e is CorruptedMediaFileException ||
        e is UnsupportedMediaFormatException ||
        e.runtimeType.toString() == 'InvalidCipherTextException') {
      if (e is CorruptedMediaFileException ||
          e is UnsupportedMediaFormatException ||
          e is StateError) {
        rethrow;
      }
      throw const CorruptedMediaFileException();
    }
    throw const CorruptedMediaFileException();
  }
}

Future<void> rangeDecryptWorkerEntry(RangeDecryptWorkerInit init) async {
  final masterKey = init.masterKey;
  final systemKey = init.systemKey;
  final responsePort = init.responsePort;
  final requests = ReceivePort();
  init.bootstrapPort.send(requests.sendPort);
  bool ctrEquals(List<int> head, List<int> magic) {
    for (int i = 0; i < 8; i++) {
      if (head[i] != magic[i]) return false;
    }
    return true;
  }

  Future<Uint8List> readExact(RandomAccessFile raf, int length) async {
    final buffer = Uint8List(length);
    int got = 0;
    while (got < length) {
      final n = await raf.readInto(buffer, got);
      if (n == 0) break;
      got += n;
    }
    if (got != length) throw const CorruptedMediaFileException();
    return buffer;
  }

  /// Whole-file decrypt, added 2026-09-17 for the photo vault.
  ///
  /// The photo grid needs every byte of a blob to draw one tile, and the old
  /// path (`FileVaultService.getPhoto` -> `decryptSystem`) ran that entire AES
  /// pass on the UI isolate, once per visible tile, all at the same moment.
  /// Measured on the dev box: 588 ms for one 3 MB photo, 2134 ms for a
  /// nine-tile grid, with zero event-loop ticks in both cases. This runs the
  /// same work inside the worker that already exists for video ranges.
  ///
  /// All four on-disk formats are served, mirroring `decryptSystem`'s routing
  /// exactly: MVKEYv1 CBC under the master DEK, MVKEYc1 CTR under the system
  /// key, MVKEYc2 CTR under the master DEK, and headerless legacy boxes CBC
  /// under the system key.
  Future<Uint8List> readAndDecryptWholeFile(String path) async {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      final fileLength = await raf.length();
      final head = Uint8List(8);
      final headRead = fileLength >= 8 ? await raf.readInto(head) : 0;
      final format = headRead == 8
          ? classifyMediaHeader(head)
          : MediaBlobFormat.legacyNoHeader;

      if (format == MediaBlobFormat.ctrV1 || format == MediaBlobFormat.ctrV2) {
        if (fileLength < 24) throw const CorruptedMediaFileException();
        final iv = await readExact(raf, 16);
        final Uint8List key;
        if (format == MediaBlobFormat.ctrV2) {
          key = masterKey;
        } else {
          final sys = systemKey;
          if (sys == null) throw StateError('System key is missing');
          key = sys;
        }
        final payloadLength = fileLength - 24;
        if (payloadLength == 0) return Uint8List(0);
        final encrypted = await readExact(raf, payloadLength);
        final out = ctrDecryptRange(
          key: key,
          iv: iv,
          encrypted: encrypted,
          offset: 0,
          length: payloadLength,
        );
        encrypted.fillRange(0, encrypted.length, 0);
        return out;
      }

      if (format == MediaBlobFormat.cbcV1) {
        // Layout is magic(8) + IV(16) + padded-CBC ciphertext. The ciphertext
        // block of a real v1 write is at least one AES block (PKCS7 always pads,
        // even for block-aligned plaintext), so anything shorter is a truncated
        // header and refused above. Mirrors the inline `decryptSystem` branch:
        // strip the magic, IV = next 16 bytes, decrypt the rest.
        if (fileLength < 24 + 16) throw const CorruptedMediaFileException();
        final iv = await readExact(raf, 16);
        final encrypted = await readExact(raf, fileLength - 24);
        final out = cbcDecryptPadded(key: masterKey, iv: iv, encrypted: encrypted);
        encrypted.fillRange(0, encrypted.length, 0);
        return out;
      }

      // Headerless legacy: the whole file is IV(16) + PKCS7-padded CBC ciphertext.
      // NOTE: `head` above already consumed the first 8 bytes (which ARE the
      // first half of the IV), so rewind to 0 before reading the IV; without
      // this the worker would read bytes 8..23 as the IV and every legacy
      // blob would report corrupt (falling back to inline, so still correct
      // but never fast).
      // Length floor mirrors inline `decryptSystem` (< 32 refuses); a real
      // legacy write is always >= 32 because PKCS7 guarantees >= 1 block.
      if (fileLength < 16 + 16 || fileLength % 16 != 0) {
        throw const CorruptedMediaFileException();
      }
      final sys = systemKey;
      if (sys == null) throw StateError('System key is missing');
      await raf.setPosition(0);
      // This format has no magic header, so the IV begins at byte 0. The 8-byte
      // probe above already consumed the first half of that IV.
      final iv = await readExact(raf, 16);
      final encrypted = await readExact(raf, fileLength - 16);
      final out = cbcDecryptPadded(key: sys, iv: iv, encrypted: encrypted);
      encrypted.fillRange(0, encrypted.length, 0);
      return out;
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }
  await for (final dynamic message in requests) {
    if (message is! Map) continue;
    if (message['cmd'] == 'stop') {
      masterKey.fillRange(0, masterKey.length, 0);
      final sys = systemKey;
      if (sys != null) sys.fillRange(0, sys.length, 0);
      requests.close();
      break;
    }
    if (message['cmd'] == 'file') {
      final int? fileId = message['id'] as int?;
      final String? filePath = message['path'] as String?;
      if (fileId == null || filePath == null) continue;
      try {
        final plaintext = await readAndDecryptWholeFile(filePath);
        responsePort.send(<String, dynamic>{'id': fileId, 'bytes': plaintext});
      } catch (e) {
        // The kinds are mapped to their exact exception types on the main
        // isolate (RangeDecryptWorker._onResponse). 'systemKeyMissing' is
        // accurate typing, not a control-flow decision: a StateError raised
        // while reading a whole file can only be "System key is missing"
        // (the master key is non-null by construction for cmd:'file'), and
        // reporting it as 'locked' would misdescribe it to any future caller.
        final kind = e is UnsupportedMediaFormatException ? 'unsupportedFormat' : e is CorruptedMediaFileException ? 'corrupted' : e is StateError ? 'systemKeyMissing' : 'unknown';
        responsePort.send(<String, dynamic>{'id': fileId, 'error': e.toString(), 'kind': kind});
      }
      continue;
    }
    final int? id = message['id'] as int?;
    final String? path = message['path'] as String?;
    final int? offset = message['offset'] as int?;
    final int? length = message['length'] as int?;
    if (id == null || path == null || offset == null || length == null) continue;
    try {
      if (offset < 0 || length <= 0) throw const CorruptedMediaFileException();
      final raf = await File(path).open(mode: FileMode.read);
      try {
        final magic = Uint8List(8);
        if (await raf.readInto(magic) != 8) throw const CorruptedMediaFileException();
        final bool isC2 = ctrEquals(magic, kMediaMagicCtrV2);
        final bool isC1 = ctrEquals(magic, kMediaMagicCtrV1);
        if (!isC1 && !isC2) throw UnsupportedMediaFormatException('range worker serves CTR blobs only');
        final iv = Uint8List(16);
        if (await raf.readInto(iv) != 16) throw const CorruptedMediaFileException();
        Uint8List key;
        if (isC2) {
          key = masterKey;
        } else {
          final sys = systemKey;
          if (sys == null) throw StateError('System key is missing');
          key = sys;
        }
        await raf.setPosition(24 + offset);
        final encrypted = Uint8List(length);
        int got = 0;
        while (got < length) {
          final n = await raf.readInto(encrypted, got);
          if (n == 0) break;
          got += n;
        }
        if (got != length) throw const CorruptedMediaFileException();
        final out = ctrDecryptRange(
          key: key,
          iv: iv,
          encrypted: encrypted,
          offset: offset,
          length: length,
        );
        encrypted.fillRange(0, encrypted.length, 0);
        // Close BEFORE replying (Windows errno-32 fix): the main isolate
        // completes its Future the moment this message lands, a test's
        // tearDown can then delete the temp dir the same instant, and on
        // Windows deleting a file that still has an open RandomAccessFile
        // handle fails with "The process cannot access the file" (errno 32;
        // POSIX allows unlinking open files, which is why this never showed
        // there). Replying after the close makes "response received" imply
        // "file handle released". Error paths below reply separately, after
        // their own close, so there is never a double send.
        await raf.close();
        responsePort.send(<String, dynamic>{'id': id, 'bytes': out});
      } finally {
        // Reached only when the try threw before the explicit close above;
        // close is idempotent, so this never breaks the normal path.
        try {
          await raf.close();
        } catch (_) {}
      }
    } catch (e) {
      final kind = e is UnsupportedMediaFormatException ? 'unsupportedFormat' : e is CorruptedMediaFileException ? 'corrupted' : e is StateError ? 'locked' : 'unknown';
      responsePort.send(<String, dynamic>{'id': id, 'error': e.toString(), 'kind': kind});
    }
  }
}

class RangeDecryptWorker {
  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _bootstrap;
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _sub;
  final Map<int, Completer<Uint8List>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;
  bool _started = false;
  bool get isAlive => _started && !_disposed && _requests != null;
  Future<void> start({required Uint8List masterKey, required Uint8List? systemKey}) async {
    if (_started) return;
    _bootstrap = ReceivePort();
    _responses = ReceivePort();
    _sub = _responses!.listen(_onResponse);
    final init = RangeDecryptWorkerInit(masterKey: masterKey, systemKey: systemKey, bootstrapPort: _bootstrap!.sendPort, responsePort: _responses!.sendPort);
    _isolate = await Isolate.spawn(rangeDecryptWorkerEntry, init);
    final first = await _bootstrap!.first.timeout(const Duration(seconds: 10), onTimeout: () => throw TimeoutException('range worker did not start'));
    _requests = first as SendPort;
    _started = true;
  }
  void _onResponse(dynamic message) {
    if (message is! Map) return;
    final int? id = message['id'] as int?;
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message.containsKey('bytes')) {
      completer.complete(message['bytes'] as Uint8List);
    } else {
      final kind = message['kind'] as String? ?? 'unknown';
      final text = message['error'] as String? ?? 'Range decrypt failed';
      if (kind == 'unsupportedFormat') { completer.completeError(UnsupportedMediaFormatException(text)); }
      else if (kind == 'corrupted') { completer.completeError(CorruptedMediaFileException(text)); }
      else if (kind == 'locked') { completer.completeError(StateError(text)); }
      else if (kind == 'systemKeyMissing') { completer.completeError(StateError(text)); }
      else { completer.completeError(Exception(text)); }
    }
  }
  Future<Uint8List> decrypt({required String path, required int offset, required int length}) {
    final requests = _requests;
    if (_disposed || !_started || requests == null) return Future.error(StateError('Range worker is not running'));
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    try {
      requests.send(<String, dynamic>{'id': id, 'path': path, 'offset': offset, 'length': length});
    } catch (e) {
      _pending.remove(id);
      completer.completeError(e);
    }
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () { _pending.remove(id); throw TimeoutException('Range decrypt timed out'); });
  }
  /// Whole-file decrypt through the worker (photo vault path, 2026-09-17).
  ///
  /// Same port protocol and same pending-map bookkeeping as [decrypt]; only the
  /// command differs, so a timeout or a lock disposes it exactly like a range
  /// request. The 30 s ceiling is generous for photos but matches the existing
  /// range behaviour, which also serves multi-megabyte video chunks.
  Future<Uint8List> decryptFile({required String path}) {
    final requests = _requests;
    if (_disposed || !_started || requests == null) return Future.error(StateError('Range worker is not running'));
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    try {
      requests.send(<String, dynamic>{'cmd': 'file', 'id': id, 'path': path});
    } catch (e) {
      _pending.remove(id);
      completer.completeError(e);
    }
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () { _pending.remove(id); throw TimeoutException('File decrypt timed out'); });
  }
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(StateError('Vault is locked'));
    }
    _pending.clear();
    try { _requests?.send(const <String, String>{'cmd': 'stop'}); } catch (_) {}
    _requests = null;
    try { await _sub?.cancel(); } catch (_) {}
    try { _bootstrap?.close(); } catch (_) {}
    try { _responses?.close(); } catch (_) {}
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
  }
}
