// lib/vault/security/breakin_log.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../crypto/vault_crypto.dart';

class BreakInLog {
  final String id;
  final String? encryptedPhotoPath;
  final String timestamp;
  final int attemptCount;

  BreakInLog({
    required this.id,
    this.encryptedPhotoPath,
    required this.timestamp,
    required this.attemptCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'encryptedPhotoPath': encryptedPhotoPath,
      'timestamp': timestamp,
      'attemptCount': attemptCount,
    };
  }

  factory BreakInLog.fromMap(Map<String, dynamic> map) {
    return BreakInLog(
      id: map['id'] as String,
      encryptedPhotoPath: map['encryptedPhotoPath'] as String?,
      timestamp: map['timestamp'] as String,
      attemptCount: map['attemptCount'] as int,
    );
  }
}

class BreakInLogService {
  static Database? _db;

  static Future<Database> _ensureDb() async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'breakin_logs.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE breakin_logs(
            id TEXT PRIMARY KEY,
            encryptedPhotoPath TEXT,
            timestamp TEXT,
            attemptCount INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  /// Records a wrong PIN attempt. If attemptCount >= 3, captures a front-camera selfie silently,
  /// encrypts it using VaultCrypto.encryptBytes, and saves it.
  static Future<void> recordAttempt(int attemptCount, VaultCrypto crypto) async {
    final db = await _ensureDb();
    final id = const Uuid().v4();
    final timestamp = DateTime.now().toIso8601String();
    String? encryptedPhotoPath;

    if (attemptCount >= 3 && !kIsWeb) {
      try {
        final cameras = await availableCameras();
        if (cameras.isNotEmpty) {
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
          final image = await controller.takePicture();
          final bytes = await image.readAsBytes();
          await controller.dispose();

          // Encrypt photo bytes
          final encryptedBytes = await crypto.encryptBytes(bytes);

          // Save encrypted photo to private docs folder
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = 'intruder_selfie_$id.enc';
          final filePath = p.join(appDir.path, fileName);
          final file = File(filePath);
          await file.writeAsBytes(encryptedBytes);
          
          encryptedPhotoPath = filePath;
        }
      } catch (e) {
        debugPrint('Silent intruder selfie capture failed: $e');
      }
    }

    final log = BreakInLog(
      id: id,
      encryptedPhotoPath: encryptedPhotoPath,
      timestamp: timestamp,
      attemptCount: attemptCount,
    );

    await db.insert(
      'breakin_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches all recorded break-in log entries in descending order (newest first).
  static Future<List<BreakInLog>> getLogs() async {
    final db = await _ensureDb();
    final List<Map<String, dynamic>> maps = await db.query(
      'breakin_logs',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => BreakInLog.fromMap(maps[i]));
  }

  /// Deletes a break-in log and its associated encrypted photo file on disk.
  static Future<void> deleteLog(String id) async {
    final db = await _ensureDb();
    
    // Retrieve log detail to find file path
    final List<Map<String, dynamic>> results = await db.query(
      'breakin_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (results.isNotEmpty) {
      final photoPath = results.first['encryptedPhotoPath'] as String?;
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          final file = File(photoPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Failed to delete encrypted photo file: $e');
        }
      }
    }

    await db.delete(
      'breakin_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
