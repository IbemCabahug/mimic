import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/export/mimic_v2_format.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mimic_v2_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Stream<List<int>> _createStream(List<int> data) async* {
    yield data;
  }

  test('Round-trip: header + JSON metadata + 3 small blobs + finish', () async {
    final file = File('${tempDir.path}/test_v2.mimic');
    final sink = file.openWrite();
    final writer = MimicV2Writer(sink);

    final timestamp = 1620000000000;
    final metadata = Uint8List.fromList(utf8.encode('{"key":"value"}'));

    writer.writeHeader(timestamp, metadata);

    final b1 = utf8.encode('blob 1 data');
    await writer.writeBlob('id-1', b1.length, _createStream(b1));

    final b2 = utf8.encode('blob 2 data longer');
    await writer.writeBlob('id-2', b2.length, _createStream(b2));

    final b3 = utf8.encode('blob 3 data');
    await writer.writeBlob('id-3', b3.length, _createStream(b3));

    await writer.finish();
    await sink.close();

    final raf = await file.open(mode: FileMode.read);
    final reader = MimicV2Reader(raf);

    final version = await reader.readHeader();
    expect(version, kMimicVersionV2);

    final readMeta = await reader.readMetadata();
    expect(readMeta, metadata);

    final e1 = await reader.readBlobEntry();
    expect(e1.id, 'id-1');
    expect(e1.length, b1.length);
    final dest1 = File('${tempDir.path}/out1').openWrite();
    await reader.copyBlobData(e1.length, dest1);
    await dest1.close();
    expect(await File('${tempDir.path}/out1').readAsBytes(), b1);

    final e2 = await reader.readBlobEntry();
    expect(e2.id, 'id-2');
    expect(e2.length, b2.length);
    final dest2 = File('${tempDir.path}/out2').openWrite();
    await reader.copyBlobData(e2.length, dest2);
    await dest2.close();
    expect(await File('${tempDir.path}/out2').readAsBytes(), b2);

    final e3 = await reader.readBlobEntry();
    expect(e3.id, 'id-3');
    expect(e3.length, b3.length);
    final dest3 = File('${tempDir.path}/out3').openWrite();
    await reader.copyBlobData(e3.length, dest3);
    await dest3.close();
    expect(await File('${tempDir.path}/out3').readAsBytes(), b3);

    final isValid = await reader.verifyTrailer();
    expect(isValid, isTrue);

    await raf.close();
  });

  test('Corruption: flip one payload byte -> verifyTrailer()==false', () async {
    final file = File('${tempDir.path}/corrupt.mimic');
    final sink = file.openWrite();
    final writer = MimicV2Writer(sink);
    writer.writeHeader(0, Uint8List(0));
    final b = utf8.encode('hello');
    await writer.writeBlob('test', b.length, _createStream(b));
    await writer.finish();
    await sink.close();

    final bytes = await file.readAsBytes();
    final corruptBytes = Uint8List.fromList(bytes);
    corruptBytes[corruptBytes.length - 35] ^= 0x01; // flip a byte in payload
    final file2 = File('${tempDir.path}/corrupt2.mimic');
    await file2.writeAsBytes(corruptBytes);

    final raf = await file2.open(mode: FileMode.read);
    final reader = MimicV2Reader(raf);
    await reader.readHeader();
    await reader.readMetadata();
    final e = await reader.readBlobEntry();
    await reader.skipBlobData(e.length);
    final isValid = await reader.verifyTrailer();
    expect(isValid, isFalse);
    await raf.close();
  });

  test('Truncation: drop the last byte -> verify fails gracefully', () async {
    final file = File('${tempDir.path}/trunc.mimic');
    final sink = file.openWrite();
    final writer = MimicV2Writer(sink);
    writer.writeHeader(0, Uint8List(0));
    await writer.finish();
    await sink.close();

    final bytes = await file.readAsBytes();
    final file2 = File('${tempDir.path}/trunc2.mimic');
    await file2.writeAsBytes(bytes.sublist(0, bytes.length - 1));

    final raf = await file2.open(mode: FileMode.read);
    final reader = MimicV2Reader(raf);
    await reader.readHeader();
    await reader.readMetadata();
    
    bool failed = false;
    try {
      final isValid = await reader.verifyTrailer();
      if (!isValid) failed = true;
    } catch (e) {
      failed = true;
    }
    expect(failed, isTrue);
    await raf.close();
  });

  test('Empty vault: header + metadata + zero blobs + finish -> verifyTrailer()==true', () async {
    final file = File('${tempDir.path}/empty.mimic');
    final sink = file.openWrite();
    final writer = MimicV2Writer(sink);
    writer.writeHeader(0, Uint8List(0));
    await writer.finish();
    await sink.close();

    final raf = await file.open(mode: FileMode.read);
    final reader = MimicV2Reader(raf);
    await reader.readHeader();
    await reader.readMetadata();
    final isValid = await reader.verifyTrailer();
    expect(isValid, isTrue);
    await raf.close();
  });
}
