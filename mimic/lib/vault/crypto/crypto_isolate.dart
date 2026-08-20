// lib/vault/crypto/crypto_isolate.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'media_format.dart';
import 'vault_exceptions.dart';

export 'vault_exceptions.dart';

/// Parameters passed to the crypto worker isolate for encryption.
class CryptoIsolateEncryptParams {
  final Uint8List key;
  final Uint8List iv;
  final String srcPath;
  final String destPath;
  final SendPort? progressPort;
  final SendPort replyPort;

  CryptoIsolateEncryptParams({
    required this.key,
    required this.iv,
    required this.srcPath,
    required this.destPath,
    this.progressPort,
    required this.replyPort,
  });
}

/// Parameters passed to the crypto worker isolate for decryption.
class CryptoIsolateDecryptParams {
  final Uint8List key;
  final String srcPath;
  final String destPath;
  final SendPort? progressPort;
  final SendPort replyPort;

  CryptoIsolateDecryptParams({
    required this.key,
    required this.srcPath,
    required this.destPath,
    this.progressPort,
    required this.replyPort,
  });
}

/// Top-level worker function running in a background isolate to encrypt a stream.
///
/// WARNING: Zeroes params.key in finally; must never be invoked directly with a live caller key.
Future<void> isolateEncryptWorker(CryptoIsolateEncryptParams params) async {
  final key = params.key;
  final iv = params.iv;
  final src = File(params.srcPath);
  final dest = File(params.destPath);
  final progressPort = params.progressPort;

  try {
    final raf = await dest.open(mode: FileMode.write);
    bool writeSucceeded = false;
    try {
      await raf.writeFrom(kMediaMagicV1);
      await raf.writeFrom(iv);

      final cipher = CBCBlockCipher(AESEngine());
      cipher.init(true, ParametersWithIV(KeyParameter(key), iv));

      final srcRaf = await src.open(mode: FileMode.read);
      try {
        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024 + 16);

        var leftover = <int>[];
        var bytesRead = 0;
        var totalBytesRead = 0;

        while ((bytesRead = await srcRaf.readInto(buffer)) > 0) {
          totalBytesRead += bytesRead;
          if (progressPort != null) {
            progressPort.send(totalBytesRead);
          }

          int offset = 0;
          int outOffset = 0;

          if (leftover.isNotEmpty) {
            final needed = 16 - leftover.length;
            if (bytesRead < needed) {
              leftover.addAll(buffer.sublist(0, bytesRead));
              continue;
            } else {
              final temp = Uint8List(16);
              temp.setRange(0, leftover.length, leftover);
              temp.setRange(leftover.length, 16, buffer.sublist(0, needed));
              cipher.processBlock(temp, 0, outBuffer, outOffset);
              outOffset += 16;
              offset = needed;
              leftover.clear();
            }
          }

          while (offset + 16 <= bytesRead) {
            cipher.processBlock(buffer, offset, outBuffer, outOffset);
            outOffset += 16;
            offset += 16;
          }

          if (outOffset > 0) {
            await raf.writeFrom(outBuffer, 0, outOffset);
          }

          if (offset < bytesRead) {
            leftover.addAll(buffer.sublist(offset, bytesRead));
          }
        }

        final padLength = 16 - leftover.length;
        final finalBlock = Uint8List(16);
        if (leftover.isNotEmpty) {
          finalBlock.setRange(0, leftover.length, leftover);
        }
        for (int i = leftover.length; i < 16; i++) {
          finalBlock[i] = padLength;
        }
        final outBlock = Uint8List(16);
        cipher.processBlock(finalBlock, 0, outBlock, 0);
        await raf.writeFrom(outBlock);
        writeSucceeded = true;
      } finally {
        await srcRaf.close();
      }
    } finally {
      await raf.flush();
      await raf.close();
      if (!writeSucceeded) {
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (_) {}
      }
    }
    params.replyPort.send(null);
  } catch (e, st) {
    final String errorKind;
    final String message;
    if (e is CorruptedMediaFileException) {
      errorKind = 'corrupted';
      message = e.message;
    } else if (e is UnsupportedMediaFormatException) {
      errorKind = 'unsupportedFormat';
      message = e.message;
    } else if (e is IOException) {
      errorKind = 'io';
      message = e.toString();
    } else {
      errorKind = 'unknown';
      message = e.toString();
    }
    params.replyPort.send({
      'errorKind': errorKind,
      'message': message,
      'stack': st.toString(),
    });
  } finally {
    params.key.fillRange(0, params.key.length, 0);
  }
}

/// Top-level worker function running in a background isolate to decrypt a stream.
///
/// WARNING: Zeroes params.key in finally; must never be invoked directly with a live caller key.
Future<void> isolateDecryptWorker(CryptoIsolateDecryptParams params) async {
  final key = params.key;
  final src = File(params.srcPath);
  final dest = File(params.destPath);
  final progressPort = params.progressPort;

  try {
    final raf = await src.open(mode: FileMode.read);
    try {
      final magicBuffer = Uint8List(kMediaMagicV1.length);
      final magicRead = await raf.readInto(magicBuffer);
      if (magicRead < kMediaMagicV1.length) {
        throw const CorruptedMediaFileException('Invalid ciphertext: missing magic header');
      }
      bool magicMatches = true;
      for (int i = 0; i < kMediaMagicV1.length; i++) {
        if (magicBuffer[i] != kMediaMagicV1[i]) {
          magicMatches = false;
          break;
        }
      }
      if (!magicMatches) {
        throw const UnsupportedMediaFormatException('Unsupported media format header');
      }

      final iv = Uint8List(16);
      final ivRead = await raf.readInto(iv);
      if (ivRead < 16) {
        throw const CorruptedMediaFileException('Invalid ciphertext: missing IV');
      }

      final destRaf = await dest.open(mode: FileMode.write);
      try {
        final cipher = CBCBlockCipher(AESEngine());
        cipher.init(false, ParametersWithIV(KeyParameter(key), iv));

        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024 + 16);
        var bytesRead = 0;
        var totalBytesRead = 0;

        var leftoverCipher = <int>[];
        Uint8List? heldPlaintextBlock;

        while ((bytesRead = await raf.readInto(buffer)) > 0) {
          totalBytesRead += bytesRead;
          if (progressPort != null) {
            progressPort.send(totalBytesRead);
          }

          int offset = 0;
          int outOffset = 0;

          if (leftoverCipher.isNotEmpty) {
            final needed = 16 - leftoverCipher.length;
            if (bytesRead < needed) {
              leftoverCipher.addAll(buffer.sublist(0, bytesRead));
              continue;
            } else {
              final temp = Uint8List(16);
              temp.setRange(0, leftoverCipher.length, leftoverCipher);
              temp.setRange(leftoverCipher.length, 16, buffer.sublist(0, needed));

              final tempOut = Uint8List(16);
              cipher.processBlock(temp, 0, tempOut, 0);

              if (heldPlaintextBlock != null) {
                outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
                outOffset += 16;
              }
              heldPlaintextBlock = tempOut;

              offset = needed;
              leftoverCipher.clear();
            }
          }

          while (offset + 16 <= bytesRead) {
            final tempOut = Uint8List(16);
            cipher.processBlock(buffer, offset, tempOut, 0);

            if (heldPlaintextBlock != null) {
              outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
              outOffset += 16;
            }
            heldPlaintextBlock = tempOut;
            offset += 16;
          }

          if (outOffset > 0) {
            await destRaf.writeFrom(outBuffer, 0, outOffset);
          }

          if (offset < bytesRead) {
            leftoverCipher.addAll(buffer.sublist(offset, bytesRead));
          }
        }

        if (leftoverCipher.isNotEmpty) {
          throw const CorruptedMediaFileException('Invalid ciphertext: not a multiple of block size');
        }

        if (heldPlaintextBlock != null) {
          final padLength = heldPlaintextBlock[15];
          if (padLength > 0 && padLength <= 16) {
            await destRaf.writeFrom(heldPlaintextBlock.sublist(0, 16 - padLength));
          } else {
            throw const CorruptedMediaFileException('Invalid PKCS7 padding');
          }
        } else {
          throw const CorruptedMediaFileException('Invalid ciphertext: empty payload');
        }
      } finally {
        await destRaf.flush();
        await destRaf.close();
      }
    } finally {
      await raf.close();
    }
    params.replyPort.send(null);
  } catch (e, st) {
    final String errorKind;
    final String message;
    if (e is CorruptedMediaFileException) {
      errorKind = 'corrupted';
      message = e.message;
    } else if (e is UnsupportedMediaFormatException) {
      errorKind = 'unsupportedFormat';
      message = e.message;
    } else if (e is IOException) {
      errorKind = 'io';
      message = e.toString();
    } else {
      errorKind = 'unknown';
      message = e.toString();
    }
    params.replyPort.send({
      'errorKind': errorKind,
      'message': message,
      'stack': st.toString(),
    });
  } finally {
    params.key.fillRange(0, params.key.length, 0);
  }
}

/// Spawns a background isolate to encrypt [srcPath] to [destPath].
Future<void> cryptoIsolateEncryptFile({
  required Uint8List key,
  required Uint8List iv,
  required String srcPath,
  required String destPath,
  SendPort? progressPort,
}) async {
  final keyForWorker = Uint8List.fromList(key);
  final replyPort = ReceivePort();
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  StreamSubscription<dynamic>? replySub;
  StreamSubscription<dynamic>? errorSub;
  StreamSubscription<dynamic>? exitSub;
  Isolate? isolate;

  try {
    final params = CryptoIsolateEncryptParams(
      key: keyForWorker,
      iv: iv,
      srcPath: srcPath,
      destPath: destPath,
      progressPort: progressPort,
      replyPort: replyPort.sendPort,
    );

    isolate = await Isolate.spawn(
      isolateEncryptWorker,
      params,
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );

    final completer = Completer<dynamic>();

    replySub = replyPort.listen((message) {
      if (!completer.isCompleted) {
        completer.complete(message);
      }
    });

    errorSub = errorPort.listen((errorData) {
      if (!completer.isCompleted) {
        String msg = 'Crypto isolate worker failed with unhandled error';
        if (errorData is List && errorData.isNotEmpty) {
          msg = errorData[0].toString();
        } else if (errorData != null) {
          msg = errorData.toString();
        }
        completer.completeError(Exception(msg));
      }
    });

    exitSub = exitPort.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Crypto isolate worker exited prematurely without returning a result'));
      }
    });

    final response = await completer.future;
    if (response is Map && response['errorKind'] != null) {
      final kind = response['errorKind'] as String;
      final message = response['message'] as String? ?? 'Crypto isolate operation failed';
      switch (kind) {
        case 'corrupted':
          throw CorruptedMediaFileException(message);
        case 'unsupportedFormat':
          throw UnsupportedMediaFormatException(message);
        case 'io':
          throw FileSystemException(message);
        case 'unknown':
        default:
          throw Exception(message);
      }
    }
  } finally {
    keyForWorker.fillRange(0, keyForWorker.length, 0);
    try {
      await replySub?.cancel();
    } catch (_) {}
    try {
      await errorSub?.cancel();
    } catch (_) {}
    try {
      await exitSub?.cancel();
    } catch (_) {}
    replyPort.close();
    errorPort.close();
    exitPort.close();
    if (isolate != null) {
      isolate.kill(priority: Isolate.beforeNextEvent);
    }
  }
}

/// Spawns a background isolate to decrypt [srcPath] to [destPath].
///
/// NOTE: Supports v1 only and must not be used for playback until the classifier is ported.
Future<void> cryptoIsolateDecryptFile({
  required Uint8List key,
  required String srcPath,
  required String destPath,
  SendPort? progressPort,
}) async {
  final keyForWorker = Uint8List.fromList(key);
  final replyPort = ReceivePort();
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  StreamSubscription<dynamic>? replySub;
  StreamSubscription<dynamic>? errorSub;
  StreamSubscription<dynamic>? exitSub;
  Isolate? isolate;

  try {
    final params = CryptoIsolateDecryptParams(
      key: keyForWorker,
      srcPath: srcPath,
      destPath: destPath,
      progressPort: progressPort,
      replyPort: replyPort.sendPort,
    );

    isolate = await Isolate.spawn(
      isolateDecryptWorker,
      params,
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );

    final completer = Completer<dynamic>();

    replySub = replyPort.listen((message) {
      if (!completer.isCompleted) {
        completer.complete(message);
      }
    });

    errorSub = errorPort.listen((errorData) {
      if (!completer.isCompleted) {
        String msg = 'Crypto isolate worker failed with unhandled error';
        if (errorData is List && errorData.isNotEmpty) {
          msg = errorData[0].toString();
        } else if (errorData != null) {
          msg = errorData.toString();
        }
        completer.completeError(Exception(msg));
      }
    });

    exitSub = exitPort.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Crypto isolate worker exited prematurely without returning a result'));
      }
    });

    final response = await completer.future;
    if (response is Map && response['errorKind'] != null) {
      final kind = response['errorKind'] as String;
      final message = response['message'] as String? ?? 'Crypto isolate operation failed';
      switch (kind) {
        case 'corrupted':
          throw CorruptedMediaFileException(message);
        case 'unsupportedFormat':
          throw UnsupportedMediaFormatException(message);
        case 'io':
          throw FileSystemException(message);
        case 'unknown':
        default:
          throw Exception(message);
      }
    }
  } finally {
    keyForWorker.fillRange(0, keyForWorker.length, 0);
    try {
      await replySub?.cancel();
    } catch (_) {}
    try {
      await errorSub?.cancel();
    } catch (_) {}
    try {
      await exitSub?.cancel();
    } catch (_) {}
    replyPort.close();
    errorPort.close();
    exitPort.close();
    if (isolate != null) {
      isolate.kill(priority: Isolate.beforeNextEvent);
    }
  }
}

