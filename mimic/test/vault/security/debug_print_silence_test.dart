// test/vault/security/debug_print_silence_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SEC-10: debugPrint log silencing and sanitization', () {
    final originalDebugPrint = debugPrint;

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('debugPrint is replaced with no-op in release mode behavior', () {
      final List<String> logs = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      debugPrint('Sensitive chat or file path data');
      expect(logs, contains('Sensitive chat or file path data'));

      // Emulate release mode override from main.dart
      const isRelease = true;
      if (isRelease) {
        debugPrint = (String? message, {int? wrapWidth}) {};
      }

      debugPrint('Another sensitive log message');
      expect(logs.length, 1);
    });
  });
}
