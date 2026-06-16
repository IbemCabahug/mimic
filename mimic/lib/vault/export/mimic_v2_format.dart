import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

const List<int> kMimicMagic = [0x4D, 0x4D, 0x49, 0x43]; // MMIC
const int kMimicVersionV1 = 0x01;
const int kMimicVersionV2 = 0x02;
const List<int> kBlobMagic = [0x42, 0x4C, 0x4F, 0x42]; // BLOB

class MimicV2Writer {
  final IOSink _sink;
  late final ByteConversionSink _hashSink;
  late final AccumulatorSink<Digest> _digestSink;
  bool _finished = false;

  MimicV2Writer(this._sink) {
    _digestSink = AccumulatorSink<Digest>();
    _hashSink = sha256.startChunkedConversion(_digestSink);
  }

  void _writeBytes(List<int> bytes) {
    _sink.add(bytes);
    _hashSink.add(bytes);
  }

  void writeHeader(int timestampMs, Uint8List jsonMetadataBytes) {
    if (_finished) throw StateError('Writer is finished');

    _writeBytes(kMimicMagic);
    _writeBytes([kMimicVersionV2]);

    final tsData = ByteData(8);
    tsData.setInt64(0, timestampMs, Endian.big);
    _writeBytes(tsData.buffer.asUint8List());

    final lenData = ByteData(4);
    lenData.setUint32(0, jsonMetadataBytes.length, Endian.big);
    _writeBytes(lenData.buffer.asUint8List());

    _writeBytes(jsonMetadataBytes);
  }

  Future<void> writeBlob(String fileId, int payloadLength, Stream<List<int>> data) async {
    if (_finished) throw StateError('Writer is finished');

    _writeBytes(kBlobMagic);

    final idBytes = utf8.encode(fileId);
    final idLenData = ByteData(2);
    idLenData.setUint16(0, idBytes.length, Endian.big);
    _writeBytes(idLenData.buffer.asUint8List());

    _writeBytes(idBytes);

    final lenData = ByteData(8);
    lenData.setUint64(0, payloadLength, Endian.big);
    _writeBytes(lenData.buffer.asUint8List());

    int totalWritten = 0;
    await for (final chunk in data) {
      if (totalWritten + chunk.length > payloadLength) {
        throw Exception('Stream provided more bytes than payloadLength');
      }
      _writeBytes(chunk);
      totalWritten += chunk.length;
    }
    if (totalWritten != payloadLength) {
      throw Exception('Stream provided fewer bytes than payloadLength');
    }
  }

  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    _hashSink.close();
    final digest = _digestSink.events.single;
    _sink.add(digest.bytes); // Write trailer
    await _sink.flush();
  }
}

class BlobEntryHeader {
  final String id;
  final int length;

  BlobEntryHeader(this.id, this.length);
}

class MimicV2Reader {
  final RandomAccessFile _raf;
  late final ByteConversionSink _hashSink;
  late final AccumulatorSink<Digest> _digestSink;

  MimicV2Reader(this._raf) {
    _digestSink = AccumulatorSink<Digest>();
    _hashSink = sha256.startChunkedConversion(_digestSink);
  }

  Future<Uint8List> _readBytes(int count) async {
    final buffer = Uint8List(count);
    int read = 0;
    while (read < count) {
      final chunk = await _raf.read(count - read);
      if (chunk.isEmpty) throw Exception('Unexpected EOF');
      buffer.setRange(read, read + chunk.length, chunk);
      read += chunk.length;
    }
    _hashSink.add(buffer);
    return buffer;
  }

  Future<int> readHeader() async {
    final magic = await _readBytes(4);
    for (int i = 0; i < 4; i++) {
      if (magic[i] != kMimicMagic[i]) throw Exception('Invalid magic');
    }
    final verBytes = await _readBytes(1);
    return verBytes[0];
  }

  Future<Uint8List> readMetadata() async {
    // Read 8B timestamp
    await _readBytes(8);
    // Read 4B length
    final lenBytes = await _readBytes(4);
    final length = ByteData.view(lenBytes.buffer).getUint32(0, Endian.big);
    // Read N metadata bytes
    final metadataBytes = await _readBytes(length);
    return metadataBytes;
  }

  Future<BlobEntryHeader> readBlobEntry() async {
    final magic = await _readBytes(4);
    for (int i = 0; i < 4; i++) {
      if (magic[i] != kBlobMagic[i]) throw Exception('Invalid blob magic');
    }

    final idLenBytes = await _readBytes(2);
    final idLen = ByteData.view(idLenBytes.buffer).getUint16(0, Endian.big);

    final idBytes = await _readBytes(idLen);
    final id = utf8.decode(idBytes);

    final payloadLenBytes = await _readBytes(8);
    final payloadLen = ByteData.view(payloadLenBytes.buffer).getUint64(0, Endian.big);

    return BlobEntryHeader(id, payloadLen);
  }

  Future<void> copyBlobData(int length, IOSink dest) async {
    int remaining = length;
    final bufferSize = 64 * 1024;
    while (remaining > 0) {
      final toRead = remaining < bufferSize ? remaining : bufferSize;
      final chunk = await _readBytes(toRead);
      dest.add(chunk);
      remaining -= chunk.length;
    }
  }

  Future<void> skipBlobData(int length) async {
    int remaining = length;
    final bufferSize = 64 * 1024;
    while (remaining > 0) {
      final toRead = remaining < bufferSize ? remaining : bufferSize;
      await _readBytes(toRead);
      remaining -= toRead;
    }
  }

  Future<bool> verifyTrailer() async {
    _hashSink.close();
    final expectedDigest = _digestSink.events.single;

    final trailer = Uint8List(32);
    int read = 0;
    while (read < 32) {
      final chunk = await _raf.read(32 - read);
      if (chunk.isEmpty) {
        return false; // Graceful failure on truncation
      }
      trailer.setRange(read, read + chunk.length, chunk);
      read += chunk.length;
    }

    for (int i = 0; i < 32; i++) {
      if (trailer[i] != expectedDigest.bytes[i]) return false;
    }
    return true;
  }
}
