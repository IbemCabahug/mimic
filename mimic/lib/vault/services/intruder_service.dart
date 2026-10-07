// lib/vault/services/intruder_service.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// Public so the Danger Zone wipe (VaultWipeService) can target these files
  /// without duplicating the naming scheme here.
  static const String filePrefix = 'intruder_';
  static const String fileExtension = '.enc';
  static const String prefKeyEnabled = 'intruder_capture_enabled';

  static const _prefix = filePrefix;
  static const _extension = fileExtension;

  static final RegExp _validIntruderFilenameRegex =
      RegExp(r'^intruder_\d+\.enc$');

  /// Validates that [filename] strictly adheres to the format `intruder_<timestamp>.enc`
  /// and contains no directory separators or traversal sequences.
  static bool isValidIntruderFilename(String filename) {
    if (filename.isEmpty) return false;
    if (p.basename(filename) != filename) return false;
    return _validIntruderFilenameRegex.hasMatch(filename);
  }

  /// Whether the user has explicitly consented to and enabled intruder capture.
  /// Defaults to false (opt-in) per Google Play / Apple camera privacy policies.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefKeyEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Updates user consent and active state for intruder capture.
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyEnabled, enabled);
  }

  Future<void> captureIntruder(VaultCrypto crypto) async {
    if (kIsWeb) return;
    if (!await isEnabled()) return;
    try {
      final capabilityProbe =
          await crypto.encryptBreakInEvidenceBytes(Uint8List(16));
      if (capabilityProbe.isEmpty) return;

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
        try {
          final bytes = await image.readAsBytes();

          final encryptedBytes = await crypto.encryptBreakInEvidenceBytes(bytes);

          final appDir = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().microsecondsSinceEpoch;
          final fileName = '$_prefix$timestamp$_extension';
          final filePath = p.join(appDir.path, fileName);
          final file = File(filePath);
          await file.writeAsBytes(encryptedBytes);
        } finally {
          try {
            final tempFile = File(image.path);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (tempDeleteError) {
            assert(() {
              debugPrint('captureIntruder temp delete failed: $tempDeleteError');
              return true;
            }());
          }
        }
      } finally {
        await controller.dispose();
      }
    } catch (e) {
      // Silent failure — never reveal capture status to the user
      assert(() {
        debugPrint('captureIntruder failed: $e');
        return true;
      }());
    }
  }

  Future<List<IntruderEntry>> getIntruderLog() async {
    if (kIsWeb) return <IntruderEntry>[];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDir.path);
      final entities = dir.listSync();

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
    if (!isValidIntruderFilename(filename)) {
      throw ArgumentError('Invalid intruder filename: $filename');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final filePath = p.canonicalize(p.join(appDir.path, filename));
    final expectedParent = p.canonicalize(appDir.path);
    if (!p.isWithin(expectedParent, filePath)) {
      throw ArgumentError('Path traversal detected: $filename');
    }
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }
    final encryptedBytes = await file.readAsBytes();
    final crypto = VaultCrypto.instance;
    return crypto.decryptBytes(encryptedBytes);
  }

  Future<void> deleteIntruderEntry(String filename) async {
    if (!isValidIntruderFilename(filename)) {
      throw ArgumentError('Invalid intruder filename: $filename');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final filePath = p.canonicalize(p.join(appDir.path, filename));
    final expectedParent = p.canonicalize(appDir.path);
    if (!p.isWithin(expectedParent, filePath)) {
      throw ArgumentError('Path traversal detected: $filename');
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
