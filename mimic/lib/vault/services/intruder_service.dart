// lib/vault/services/intruder_service.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../crypto/vault_crypto.dart';

class IntruderEntry {
  final String filename;
  final DateTime timestamp;

  const IntruderEntry({required this.filename, required this.timestamp});

  factory IntruderEntry.fromFilename(String filename) {
    final base = p.basenameWithoutExtension(filename);
    final tsPart = base.replaceFirst('intruder_', '');
    final microseconds = int.tryParse(tsPart);
    if (microseconds != null) {
      return IntruderEntry(
        filename: filename,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(microseconds),
      );
    }
    return IntruderEntry(
      filename: filename,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class IntruderService {
  static const _prefix = 'intruder_';
  static const _extension = '.enc';

  Future<void> captureIntruder(VaultCrypto crypto) async {
    if (kIsWeb) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      try {
        final image = await controller.takePicture();
        final bytes = await image.readAsBytes();

        final encryptedBytes = await crypto.encryptBytes(bytes);

        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final fileName = '$_prefix$timestamp$_extension';
        final filePath = p.join(appDir.path, fileName);
        final file = File(filePath);
        await file.writeAsBytes(encryptedBytes);
      } finally {
        await controller.dispose();
      }
    } catch (_) {
      // Silent failure — never reveal capture status to the user
    }
  }

  Future<List<IntruderEntry>> getIntruderLog() async {
    if (kIsWeb) return <IntruderEntry>[];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDir.path);
      final entities = await dir.list().toList();

      final entries = <IntruderEntry>[];
      for (final entity in entities) {
        if (entity is File &&
            p.basename(entity.path).startsWith(_prefix) &&
            p.extension(entity.path) == _extension) {
          entries.add(IntruderEntry.fromFilename(p.basename(entity.path)));
        }
      }

      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (_) {
      return <IntruderEntry>[];
    }
  }

  Future<Uint8List> decryptIntruderImage(String filename) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(appDir.path, filename);
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }
    final encryptedBytes = await file.readAsBytes();
    final crypto = VaultCrypto.instance;
    return crypto.decryptBytes(encryptedBytes);
  }

  Future<void> deleteIntruderEntry(String filename) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(appDir.path, filename);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
