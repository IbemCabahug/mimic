// test/vault/services/video_thumbnail_service_test.dart

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/video_thumbnail_service.dart';

void main() {
  // NOTE: the binary messenger is deliberately NOT mocked here. The test
  // binding's reply hardening rejects the growable-buffer view that
  // `StandardMethodCodec.encodeSuccessEnvelope` returns ("Invalid argument:
  // _ByteDataView"), which breaks every successful-frame case through no fault
  // of the service. The service takes an `invokeExtract` seam for tests; the
  // real channel is exercised on the device.
  final frameBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

  late List<String> extractCalls; // URL paths, in call order
  late Future<Uint8List?> Function(String url, int maxWidthPx)? responder;

  VideoThumbnailService service({
    Future<Uri?> Function(String id)? resolveStreamUrl,
    Duration? requestTimeout,
  }) {
    extractCalls = <String>[];
    responder = null;
    return VideoThumbnailService(
      resolveStreamUrl: resolveStreamUrl ??
          (id) async => Uri.parse('http://127.0.0.1:1/media/$id'),
      requestTimeout: requestTimeout ?? const Duration(seconds: 5),
      invokeExtract: (url, maxWidthPx) async {
        extractCalls.add(Uri.parse(url).path);
        return responder?.call(url, maxWidthPx);
      },
    );
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: 'condition not met within 2s');
  }

  test('captures a frame into the cache and fires onReady', () async {
    final ready = <String>[];
    final svc = service();
    final sub = svc.onReady.listen(ready.add);
    responder = (_, _) async => frameBytes;

    svc.request('v1');
    await waitFor(() => svc.cachedFor('v1') != null);

    expect(ready, contains('v1'));
    expect(extractCalls, hasLength(1));
    expect(extractCalls.single, contains('/media/v1'));
    await sub.cancel();
  });

  test('a null frame and a failed extraction both leave the tile silent', () async {
    final svc = service();
    responder = (_, _) async => null;
    svc.request('v1');
    await waitFor(() => extractCalls.isNotEmpty);
    responder = (_, _) async => throw PlatformException(code: 'broken');
    svc.request('v2');

    await waitFor(() => !svc.isPending);
    expect(svc.cachedFor('v1'), isNull);
    expect(svc.cachedFor('v2'), isNull);
  });

  test('a wedged platform call is cut off by the request timeout', () async {
    final svc = service(requestTimeout: const Duration(milliseconds: 30));
    final never = Completer<Uint8List?>();
    responder = (_, _) => never.future;

    svc.request('v1');
    await waitFor(() => extractCalls.isNotEmpty);
    await waitFor(() => !svc.isPending);

    expect(svc.cachedFor('v1'), isNull);
  });

  test('duplicate requests collapse into one extraction', () async {
    final svc = service();
    responder = (_, _) async => frameBytes;

    svc.request('v1');
    svc.request('v1');
    svc.request('v1', priority: true);
    await waitFor(() => svc.cachedFor('v1') != null);
    await settle();

    expect(extractCalls, hasLength(1));
  });

  test('priority jumps ahead of work queued earlier', () async {
    final gate = Completer<void>();
    final svc = service();
    responder = (url, _) async {
      if (url.contains('/media/a')) {
        await gate.future;
      }
      return frameBytes;
    };

    svc.request('a');
    svc.request('b');
    await waitFor(() => extractCalls.isNotEmpty); // a is held open
    svc.request('c', priority: true); // must pass b
    gate.complete();
    await waitFor(() => !svc.isPending);

    expect(extractCalls, <String>['/media/a', '/media/c', '/media/b']);
  });

  test('clear() wipes frames, queued work and in-flight marks', () async {
    final gate = Completer<void>();
    final svc = service();
    responder = (url, _) async {
      if (url.contains('/media/a')) {
        await gate.future;
      }
      return frameBytes;
    };

    svc.request('a');
    svc.request('b');
    await waitFor(() => extractCalls.isNotEmpty); // a in flight, b queued

    svc.clear(); // the vault locked mid-generation
    gate.complete();
    await settle();

    expect(svc.cachedFor('a'), isNull, reason: 'a finished after the wipe');
    expect(svc.cachedFor('b'), isNull);
    expect(extractCalls, <String>['/media/a'], reason: 'b must never extract');

    // The wipe also cleared the in-flight mark, so a new unlock can re-request.
    responder = (_, _) async => frameBytes;
    svc.request('a');
    await waitFor(() => svc.cachedFor('a') != null);
    expect(extractCalls, hasLength(2));
  });

  test('legacy blobs resolve to no URL and never reach the channel', () async {
    final svc = service(
      resolveStreamUrl: (id) async =>
          id == 'legacy' ? null : Uri.parse('http://x/$id'),
    );
    responder = (_, _) async => frameBytes;

    svc.request('legacy');
    svc.request('c2');
    await waitFor(() => svc.cachedFor('c2') != null);
    await waitFor(() => !svc.isPending);

    expect(extractCalls, <String>['/c2']);
    expect(svc.cachedFor('legacy'), isNull);
  });

  test('a failed video is not extracted again until the vault relocks', () async {
    final svc = service();
    responder = (_, _) async => throw PlatformException(code: 'broken');

    svc.request('bad');
    await waitFor(() => !svc.isPending);

    // A frameless tile re-requests itself on every rebuild, so the failure must
    // be remembered or the same extraction is retried on each state change.
    svc.request('bad');
    svc.request('bad', priority: true);
    await settle();
    expect(extractCalls, hasLength(1), reason: 'the failure is remembered');

    // A relock-then-unlock must try once more: that is how a video F24 later
    // migrates starts showing a thumbnail.
    responder = (_, _) async => frameBytes;
    svc.clear();
    svc.request('bad');
    await waitFor(() => svc.cachedFor('bad') != null);
    expect(extractCalls, hasLength(2));
  });

  test('the cache notifier mirrors ready events and wipe()', () async {
    final svc = service();
    final notifier = VideoThumbnailCacheNotifier(svc);
    addTearDown(notifier.dispose);
    responder = (_, _) async => frameBytes;

    svc.request('v1');
    await waitFor(() => notifier.state.containsKey('v1'));
    expect(notifier.state['v1'], same(frameBytes));

    notifier.wipe();
    expect(notifier.state, isEmpty);
    expect(svc.cachedFor('v1'), isNull);
  });
}
