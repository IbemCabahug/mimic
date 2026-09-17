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
  await for (final dynamic message in requests) {
    if (message is! Map) continue;
    if (message['cmd'] == 'stop') {
      masterKey.fillRange(0, masterKey.length, 0);
      final sys = systemKey;
      if (sys != null) sys.fillRange(0, sys.length, 0);
      requests.close();
      break;
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
