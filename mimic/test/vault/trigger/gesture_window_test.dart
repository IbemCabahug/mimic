// test/vault/trigger/gesture_window_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/trigger/gesture_window.dart';

void main() {
  group('trailingWindow', () {
    test(
      'returns the full history when history length exactly matches requested length',
      () {
        final history = [1, 2, 0, 3];
        final result = trailingWindow(history, 4);
        expect(result, equals([1, 2, 0, 3]));
      },
    );

    test(
      'returns only the trailing slice when history is longer than requested length',
      () {
        final history = [5, 6, 7, 1, 2, 0, 3];
        final result = trailingWindow(history, 4);
        expect(result, equals([1, 2, 0, 3]));
      },
    );

    test('returns null when history is shorter than requested length', () {
      final history = [1, 2, 3];
      expect(trailingWindow(history, 4), isNull);
      expect(trailingWindow(history, 5), isNull);
    });

    test('returns null for empty history', () {
      expect(trailingWindow([], 4), isNull);
      expect(trailingWindow([], 1), isNull);
    });

    test('returns null when requested length is zero or negative', () {
      final history = [1, 2, 3, 4];
      expect(trailingWindow(history, 0), isNull);
      expect(trailingWindow(history, -1), isNull);
      expect(trailingWindow(history, -5), isNull);
      expect(trailingWindow([], 0), isNull);
    });

    test('returns single element list when requested length is one', () {
      final history = [4, 7, 2];
      expect(trailingWindow(history, 1), equals([2]));
    });

    test(
      'preserves original history and returns an independent mutable list',
      () {
        final original = [1, 2, 3, 4, 5];
        final window = trailingWindow(original, 3);

        expect(window, equals([3, 4, 5]));

        // Mutate the returned window
        window![0] = 99;
        window.add(100);

        // Original history must remain completely unaffected
        expect(original, equals([1, 2, 3, 4, 5]));
      },
    );
  });
}
