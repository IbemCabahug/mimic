// test/vault/screens/photo_viewer_test.dart
//
// F8 — "Photo viewer zoom on first tap".
//
// The defect: zoom needed a SECOND double-tap to engage. Root cause was not in
// the zoom maths but in the load plumbing — the load future was created inside
// itemBuilder, so the parent setState that the zoom itself triggers (through
// onZoomChanged) handed FutureBuilder a brand-new future. FutureBuilder
// dropped to ConnectionState.waiting, tore _ZoomablePhoto down, and its
// TransformationController — which held the just-computed 2.5x matrix — went
// with it. The photo snapped back to 1.0, and the second double-tap appeared
// to be the one that worked only because by then _isZoomed was already true,
// so no rebuild was triggered.
//
// These tests pin the behaviour, not the implementation: what must be true is
// that ONE double-tap leaves the photo zoomed, and that the bytes for a photo
// are decrypted once per viewing rather than once per rebuild.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/screens/photo_viewer_screen.dart';
import 'package:mimic/vault/services/file_vault_service.dart';

/// A real, decodable 1x1 PNG. Image.memory must actually paint, otherwise the
/// viewer would be testing its error path instead of its zoom path.
const String _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

Uint8List get _pngBytes => Uint8List.fromList(base64Decode(_png1x1));

PhotoMeta _photo(String id) => PhotoMeta(
      id: id,
      mimeType: 'image/png',
      size: _pngBytes.length,
      createdAt: DateTime(2026, 1, 1),
    );

/// A double-tap as the platform delivers it: two taps inside the double-tap
/// window, with a real gap so the gesture arena can resolve it.
Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 40));
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 20));
}

double _scaleOf(WidgetTester tester) {
  final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
  return viewer.transformationController!.value.getMaxScaleOnAxis();
}

void main() {
  /// Counts loads per photo id and lets each test decide what to return.
  late Map<String, int> loads;
  late Map<String, Future<Uint8List?> Function()> loaders;

  setUp(() {
    loads = <String, int>{};
    loaders = <String, Future<Uint8List?> Function()>{};
  });

  Future<Uint8List?> load(String id) {
    loads[id] = (loads[id] ?? 0) + 1;
    final loader = loaders[id];
    if (loader != null) return loader();
    return Future.value(_pngBytes);
  }

  /// Pumps the viewer inside a host that can force a parent rebuild WITHOUT
  /// recreating the viewer's State — exactly what the real grid does when it
  /// refreshes, and exactly what the zoom's own setState does.
  ///
  /// [settle] exists for the empty-list guard: that branch shows a spinner,
  /// and a spinner's animation never settles, so pumpAndSettle would time out
  /// on a passing build.
  Future<StateSetter> pumpViewer(
    WidgetTester tester, {
    required List<PhotoMeta> photos,
    int initialIndex = 0,
    bool settle = true,
  }) async {
    late StateSetter setHostState;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return PhotoViewerScreen(
                photos: photos,
                initialIndex: initialIndex,
                loadBytes: load,
                onDelete: (_) {},
                onRestore: (_) {},
              );
            },
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return setHostState;
  }
  group('F8 · zoom engages on the first double-tap', () {
    testWidgets('the FIRST double-tap leaves the photo zoomed (regression guard)',
        (WidgetTester tester) async {
      await pumpViewer(tester, photos: [_photo('p1')]);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(_scaleOf(tester), 1.0, reason: 'the photo starts unzoomed');

      await _doubleTap(tester, tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // The whole point of F8: one double-tap, not two.
      expect(_scaleOf(tester), greaterThan(2.0),
          reason: 'ONE double-tap must leave the photo zoomed in, not reset it');
      expect(_scaleOf(tester), closeTo(2.5, 0.01),
          reason: 'the zoom target is the documented 2.5x');
    });

    testWidgets('a second double-tap toggles back out to 1.0',
        (WidgetTester tester) async {
      await pumpViewer(tester, photos: [_photo('p1')]);
      final center = tester.getCenter(find.byType(InteractiveViewer));

      await _doubleTap(tester, center);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_scaleOf(tester), closeTo(2.5, 0.01));

      // Fixing the first tap must not break the toggle it was paired with.
      await _doubleTap(tester, center);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_scaleOf(tester), closeTo(1.0, 0.01));
    });

    testWidgets('the zoom causes no reload and no spinner',
        (WidgetTester tester) async {
      await pumpViewer(tester, photos: [_photo('p1')]);
      expect(loads['p1'], 1, reason: 'the first paint loads the photo once');

      await _doubleTap(tester, tester.getCenter(find.byType(InteractiveViewer)));

      // Checked BEFORE settling: this is the instant the old code showed a
      // spinner, because FutureBuilder had been handed a fresh future.
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'a rebuild must not re-enter the loading state');
      expect(find.byType(InteractiveViewer), findsOneWidget,
          reason: 'the zoom widget must survive the rebuild that the zoom triggers');

      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(loads['p1'], 1,
          reason: 'one photo view decrypts the bytes exactly once, however many rebuilds happen');
    });

    testWidgets('repeated zoom toggles still load the photo only once',
        (WidgetTester tester) async {
      final rebuild = await pumpViewer(tester, photos: [_photo('p1')]);
      final center = tester.getCenter(find.byType(InteractiveViewer));

      for (int i = 0; i < 3; i++) {
        await _doubleTap(tester, center);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }
      // Plus an unrelated parent rebuild, as the grid would emit.
      rebuild(() {});
      await tester.pumpAndSettle();

      expect(loads['p1'], 1, reason: 'the cache is keyed by photo id and is not invalidated by rebuilds');
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
  group('F8 · per-photo load cache', () {
    testWidgets('a removed photo drops its cached bytes, so re-adding the id reloads',
        (WidgetTester tester) async {
      await pumpViewer(tester, photos: [_photo('p1')]);
      expect(loads['p1'], 1);

      // The grid emits a list without p1: a delete, or a restore-to-gallery.
      await pumpViewer(tester, photos: [_photo('p2')]);
      expect(loads['p2'], 1);

      // The same id returns later. It must decrypt again rather than replay a
      // stale result that may have been deleted from disk in between.
      await pumpViewer(tester, photos: [_photo('p1')]);
      expect(loads['p1'], 2,
          reason: 'bytes must not outlive the photo entry that owned them');
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('a failed decrypt is not cached, so the viewer can recover',
        (WidgetTester tester) async {
      loaders['p1'] = () async => throw StateError('decrypt failed');
      final rebuild = await pumpViewer(tester, photos: [_photo('p1')]);

      expect(loads['p1'], 1);
      expect(find.byIcon(Icons.broken_image), findsOneWidget,
          reason: 'a failed decrypt shows the placeholder, not a stuck spinner');
      expect(find.byType(InteractiveViewer), findsNothing);

      // The failure clears, and the owner triggers any rebuild at all.
      loaders['p1'] = () async => _pngBytes;
      rebuild(() {});
      await tester.pumpAndSettle();

      expect(loads['p1'], 2, reason: 'a failure must not be cached for the session');
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget,
          reason: 'the retry shows the photo');
    });

    testWidgets('a missing photo (null bytes) is retryable too',
        (WidgetTester tester) async {
      loaders['p1'] = () async => null;
      final rebuild = await pumpViewer(tester, photos: [_photo('p1')]);

      expect(find.byIcon(Icons.broken_image), findsOneWidget);

      loaders['p1'] = () async => _pngBytes;
      rebuild(() {});
      await tester.pumpAndSettle();

      expect(loads['p1'], 2, reason: 'a null result must not be cached either');
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('a successful load IS cached, so ordinary rebuilds stay free',
        (WidgetTester tester) async {
      final rebuild = await pumpViewer(tester, photos: [_photo('p1')]);

      for (int i = 0; i < 4; i++) {
        rebuild(() {});
        await tester.pumpAndSettle();
      }

      // The counterpart to the retry tests: caching must not have been
      // disabled wholesale while fixing the failure path.
      expect(loads['p1'], 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('F8 · other viewer behaviour is untouched', () {
    testWidgets('the viewer keeps rendering its actions and its empty-list guard',
        (WidgetTester tester) async {
      await pumpViewer(tester, photos: [_photo('p1')]);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.unarchive), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      // The empty-list branch is DEFENSIVE, not a state an owner can reach:
      // the grid always pushes the viewer with the tapped photo, and the
      // viewer pops itself once the list is down to one (see the
      // widget.photos.length <= 1 checks in _deleteCurrent/_restoreCurrent).
      // It therefore shows a transient spinner with no page to show. Assert
      // the guard holds and nothing throws — but pump, never pumpAndSettle,
      // because that spinner's animation never settles by design.
      await pumpViewer(tester, photos: const <PhotoMeta>[], settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull,
          reason: 'an empty list must be guarded, never a crash');
      expect(find.byType(InteractiveViewer), findsNothing,
          reason: 'there is no page to zoom');
    });
  });
}
