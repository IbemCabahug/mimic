// test/vault/services/media_format_report_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/services/media_format_report.dart';

void main() {
  group('media format report (M12)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('media_format_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    Future<File> resolveBlob(String id) async {
      return File(p.join(tempDir.path, id));
    }

    test('T1 mixed set, exact counts', () async {
      final filler200 = List<int>.filled(200, 0x42);

      // 5 video ids
      final vC2 = await resolveBlob('v_c2');
      await vC2.writeAsBytes([...kMediaMagicCtrV2, ...filler200]);

      final vC1 = await resolveBlob('v_c1');
      await vC1.writeAsBytes([...kMediaMagicCtrV1, ...filler200]);

      final vV1 = await resolveBlob('v_v1');
      await vV1.writeAsBytes([...kMediaMagicV1, ...filler200]);

      final vLegacy = await resolveBlob('v_legacy');
      final nonMagic16 = List<int>.filled(16, 0xAA);
      await vLegacy.writeAsBytes([...nonMagic16, ...filler200]);

      // v_missing has NO file created

      // 2 photo ids
      final pV1 = await resolveBlob('p_v1');
      await pV1.writeAsBytes([...kMediaMagicV1, ...filler200]);

      final pLegacy = await resolveBlob('p_legacy');
      await pLegacy.writeAsBytes([...nonMagic16, ...filler200]);

      // 1 document id
      final dV1 = await resolveBlob('d_v1');
      await dV1.writeAsBytes([...kMediaMagicV1, ...filler200]);

      final report = await buildMediaFormatReport(
        videoIds: ['v_c2', 'v_c1', 'v_v1', 'v_legacy', 'v_missing'],
        photoIds: ['p_v1', 'p_legacy'],
        documentIds: ['d_v1'],
        resolveBlob: resolveBlob,
      );

      // Assert videos
      expect(report.videos.total, 5);
      expect(report.videos.ctrV2, 1);
      expect(report.videos.ctrV1, 1);
      expect(report.videos.cbcV1, 1);
      expect(report.videos.legacyNoHeader, 1);
      expect(report.videos.missingFile, 1);
      expect(
        report.videos.total,
        report.videos.cbcV1 +
            report.videos.ctrV1 +
            report.videos.ctrV2 +
            report.videos.legacyNoHeader +
            report.videos.missingFile,
      );

      // Assert photos
      expect(report.photos.total, 2);
      expect(report.photos.cbcV1, 1);
      expect(report.photos.legacyNoHeader, 1);
      expect(report.photos.ctrV1, 0);
      expect(report.photos.ctrV2, 0);
      expect(report.photos.missingFile, 0);
      expect(
        report.photos.total,
        report.photos.cbcV1 +
            report.photos.ctrV1 +
            report.photos.ctrV2 +
            report.photos.legacyNoHeader +
            report.photos.missingFile,
      );

      // Assert documents
      expect(report.documents.total, 1);
      expect(report.documents.cbcV1, 1);
      expect(report.documents.legacyNoHeader, 0);
      expect(report.documents.ctrV1, 0);
      expect(report.documents.ctrV2, 0);
      expect(report.documents.missingFile, 0);
      expect(
        report.documents.total,
        report.documents.cbcV1 +
            report.documents.ctrV1 +
            report.documents.ctrV2 +
            report.documents.legacyNoHeader +
            report.documents.missingFile,
      );
    });

    test('T2 a file shorter than 8 bytes is counted as very old and does not throw', () async {
      final pShort = await resolveBlob('p_short');
      await pShort.writeAsBytes([0x01, 0x02, 0x03]);

      final report = await buildMediaFormatReport(
        videoIds: [],
        photoIds: ['p_short'],
        documentIds: [],
        resolveBlob: resolveBlob,
      );

      expect(report.photos.total, 1);
      expect(report.photos.legacyNoHeader, 1);
      expect(report.photos.cbcV1, 0);
      expect(report.photos.ctrV1, 0);
      expect(report.photos.ctrV2, 0);
      expect(report.photos.missingFile, 0);
      expect(
        report.photos.total,
        report.photos.cbcV1 +
            report.photos.ctrV1 +
            report.photos.ctrV2 +
            report.photos.legacyNoHeader +
            report.photos.missingFile,
      );
    });

    test('T3 empty input', () async {
      final report = await buildMediaFormatReport(
        videoIds: [],
        photoIds: [],
        documentIds: [],
        resolveBlob: resolveBlob,
      );

      expect(report.videos.total, 0);
      expect(report.videos.cbcV1, 0);
      expect(report.videos.ctrV1, 0);
      expect(report.videos.ctrV2, 0);
      expect(report.videos.legacyNoHeader, 0);
      expect(report.videos.missingFile, 0);

      expect(report.photos.total, 0);
      expect(report.photos.cbcV1, 0);
      expect(report.photos.ctrV1, 0);
      expect(report.photos.ctrV2, 0);
      expect(report.photos.legacyNoHeader, 0);
      expect(report.photos.missingFile, 0);

      expect(report.documents.total, 0);
      expect(report.documents.cbcV1, 0);
      expect(report.documents.ctrV1, 0);
      expect(report.documents.ctrV2, 0);
      expect(report.documents.legacyNoHeader, 0);
      expect(report.documents.missingFile, 0);
    });

    test('T4 the report never modifies a blob', () async {
      final filler200 = List<int>.filled(200, 0x77);

      final fC2 = await resolveBlob('f_c2');
      await fC2.writeAsBytes([...kMediaMagicCtrV2, ...filler200]);

      final fC1 = await resolveBlob('f_c1');
      await fC1.writeAsBytes([...kMediaMagicCtrV1, ...filler200]);

      final fV1 = await resolveBlob('f_v1');
      await fV1.writeAsBytes([...kMediaMagicV1, ...filler200]);

      final beforeC2 = await fC2.readAsBytes();
      final beforeC1 = await fC1.readAsBytes();
      final beforeV1 = await fV1.readAsBytes();

      final lenBeforeC2 = await fC2.length();
      final lenBeforeC1 = await fC1.length();
      final lenBeforeV1 = await fV1.length();

      final report = await buildMediaFormatReport(
        videoIds: ['f_c2'],
        photoIds: ['f_c1'],
        documentIds: ['f_v1'],
        resolveBlob: resolveBlob,
      );

      expect(report.videos.ctrV2, 1);
      expect(report.photos.ctrV1, 1);
      expect(report.documents.cbcV1, 1);

      final afterC2 = await fC2.readAsBytes();
      final afterC1 = await fC1.readAsBytes();
      final afterV1 = await fV1.readAsBytes();

      expect(afterC2, equals(beforeC2));
      expect(afterC1, equals(beforeC1));
      expect(afterV1, equals(beforeV1));

      expect(await fC2.length(), equals(lenBeforeC2));
      expect(await fC1.length(), equals(lenBeforeC1));
      expect(await fV1.length(), equals(lenBeforeV1));
    });
  });
}
