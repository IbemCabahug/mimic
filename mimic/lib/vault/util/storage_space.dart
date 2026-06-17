import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class StorageSpace {
  static const MethodChannel _channel = MethodChannel('mimic/storage');

  static Future<int> availableBytes(String dirPath) async {
    if (kIsWeb) return 1 << 62;
    try {
      final int? free = await _channel.invokeMethod<int>('getAvailableBytes', {'path': dirPath});
      return free ?? (1 << 62);
    } catch (_) {
      return 1 << 62;
    }
  }
}
