// lib/vault/services/media_format_report.dart

import 'dart:io';
import 'dart:typed_data';
import '../crypto/media_format.dart';

class CategoryFormatCounts {
  final int total; // number of ids that were checked
  final int cbcV1;
  final int ctrV1;
  final int ctrV2;
  final int legacyNoHeader;
  final int missingFile; // metadata exists but no file on disk

  const CategoryFormatCounts({
    required this.total,
    required this.cbcV1,
    required this.ctrV1,
    required this.ctrV2,
    required this.legacyNoHeader,
    required this.missingFile,
  });
}

class MediaFormatReport {
  final CategoryFormatCounts videos;
  final CategoryFormatCounts photos;
  final CategoryFormatCounts documents;

  const MediaFormatReport({
    required this.videos,
    required this.photos,
    required this.documents,
  });
}

Future<MediaFormatReport> buildMediaFormatReport({
  required List<String> videoIds,
  required List<String> photoIds,
  required List<String> documentIds,
  required Future<File> Function(String id) resolveBlob,
}) async {
  final videoCounts = await _countCategory(videoIds, resolveBlob);
  final photoCounts = await _countCategory(photoIds, resolveBlob);
  final docCounts = await _countCategory(documentIds, resolveBlob);

  return MediaFormatReport(
    videos: videoCounts,
    photos: photoCounts,
    documents: docCounts,
  );
}

Future<CategoryFormatCounts> _countCategory(
  List<String> ids,
  Future<File> Function(String id) resolveBlob,
) async {
  int cbcV1 = 0;
  int ctrV1 = 0;
  int ctrV2 = 0;
  int legacyNoHeader = 0;
  int missingFile = 0;

  for (final id in ids) {
    try {
      final file = await resolveBlob(id);
      if (!await file.exists()) {
        missingFile++;
        continue;
      }

      RandomAccessFile? raf;
      try {
        raf = await file.open(mode: FileMode.read);
        final buffer = Uint8List(8);
        final bytesRead = await raf.readInto(buffer);
        final headerBytes = bytesRead == 8 ? buffer : buffer.sublist(0, bytesRead);
        final format = classifyMediaHeader(headerBytes);
        switch (format) {
          case MediaBlobFormat.cbcV1:
            cbcV1++;
            break;
          case MediaBlobFormat.ctrV1:
            ctrV1++;
            break;
          case MediaBlobFormat.ctrV2:
            ctrV2++;
            break;
          case MediaBlobFormat.legacyNoHeader:
            legacyNoHeader++;
            break;
        }
      } catch (_) {
        missingFile++;
      } finally {
        if (raf != null) {
          try {
            await raf.close();
          } catch (_) {}
        }
      }
    } catch (_) {
      missingFile++;
    }
  }

  // Invariant: total == cbcV1 + ctrV1 + ctrV2 + legacyNoHeader + missingFile
  final total = ids.length;
  return CategoryFormatCounts(
    total: total,
    cbcV1: cbcV1,
    ctrV1: ctrV1,
    ctrV2: ctrV2,
    legacyNoHeader: legacyNoHeader,
    missingFile: missingFile,
  );
}
