// lib/vault/services/video_thumbnail_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_stream_server.dart';
import 'video_vault_service.dart';

/// F23 — thumbnails for the video vault, in memory only.
///
/// Register constraint (2026-08-22, reaffirmed by the 2026-09-16 design note in
/// `future_feature.md`): a thumbnail is a decrypted frame of private content, so
/// frames live in memory for the current unlock ONLY — never on disk, never in
/// any system media store or cache directory — and [VideoThumbnailService.clear]
/// wipes everything the moment the vault locks. Frames are captured by the
/// Android side of the `mimic/video_thumbnail` channel (MediaMetadataRetriever)
/// reading from the vault's own loopback streaming server — the same
/// range-capable c2 decrypt source the player uses — so no plaintext ever lands
/// on storage and no new package enters the app.
class VideoThumbnailService {
  VideoThumbnailService({
    required this.resolveStreamUrl,
    this.maxWidthPx = 640,
    this.requestTimeout = const Duration(seconds: 25),
    @visibleForTesting Future<Uint8List?> Function(String url, int maxWidthPx)?
        invokeExtract,
  }) : _invokeExtractOverride = invokeExtract;

  /// The production channel. Tests do NOT drive this — the test binding's
  /// messenger rejects the growable-buffer view that `encodeSuccessEnvelope`
  /// returns ("Invalid argument: _ByteDataView"), which is a hardening of the
  /// reply path, not a defect in this service; tests inject [invokeExtract]
  /// instead, and the channel itself is exercised on the device.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('mimic/video_thumbnail');

  /// Tile width to ask from the retriever. The vault grid is two columns, so
  /// 640 device pixels cover a tile on the test device without upscaling.
  final int maxWidthPx;

  /// MediaMetadataRetriever has no timeout of its own; a wedged read must not
  /// wedge the queue, so the await is bounded here. Injectable for tests.
  final Duration requestTimeout;

  /// Where a video's decrypted bytes can be read from. The production resolver
  /// hands back the vault's own loopback streaming URL and answers null for a
  /// legacy blob (see [resolveThumbnailStreamUrl]).
  final Future<Uri?> Function(String id) resolveStreamUrl;
  final Future<Uint8List?> Function(String url, int maxWidthPx)?
      _invokeExtractOverride;

  final Map<String, Uint8List> _cache = {};

  /// Ids that have already failed. A tile rebuilds on every other tile's frame
  /// landing, and a frameless tile re-requests itself at the queue head, so
  /// without this an unthumbnailable video (legacy blob, missing blob, broken
  /// file) would be attempted again and again. Cleared by [clear], so the next
  /// unlock tries once more — which is also how a video F24 later migrates
  /// starts showing a thumbnail.
  final Set<String> _unavailable = {};
  final Set<String> _inFlight = {};
  final List<String> _queue = [];
  final StreamController<String> _ready = StreamController<String>.broadcast();
  bool _draining = false;
  int _generation = 0;

  Uint8List? cachedFor(String id) => _cache[id];

  bool get isPending => _queue.isNotEmpty || _inFlight.isNotEmpty;

  /// Fires with a video id the moment its frame lands in the cache.
  Stream<String> get onReady => _ready.stream;

  /// Queue one video for its thumbnail. [priority] puts it at the head of the
  /// queue — used by tiles that are just becoming visible, so what the owner is
  /// looking at fills first. Duplicate requests collapse into one extraction.
  void request(String id, {bool priority = false}) {
    if (_cache.containsKey(id) ||
        _inFlight.contains(id) ||
        _unavailable.contains(id)) {
      return;
    }
    _queue.remove(id);
    if (priority) {
      _queue.insert(0, id);
    } else {
      _queue.add(id);
    }
    unawaited(_drain());
  }

  /// The register constraint's single wipe point: called when the vault locks.
  /// Drops cached frames, queued work and in-flight marks. The next unlock
  /// regenerates whatever the grid is showing. An extraction already running on
  /// the platform side finishes into a cache that no longer exposes it — the
  /// generation counter below makes that guarantee explicit rather than lucky.
  void clear() {
    _generation++;
    _cache.clear();
    _queue.clear();
    _inFlight.clear();
    _unavailable.clear();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        _inFlight.add(id);
        final generation = _generation;
        Uint8List? bytes;
        try {
          final url = await resolveStreamUrl(id);
          if (url != null) {
            final invoke = _invokeExtractOverride;
            bytes = invoke != null
                ? await invoke(url.toString(), maxWidthPx).timeout(requestTimeout)
                : await channel
                    .invokeMethod<Uint8List>('extractFrame',
                        <String, Object>{'url': url.toString(), 'maxWidthPx': maxWidthPx})
                    .timeout(requestTimeout);
          }
        } catch (_) {
          // Missing blob, legacy format, server gone mid-read, timeout — every
          // failure means the same thing: no thumbnail. The tile keeps its
          // placeholder and nothing is reported; thumbnails are best-effort.
          bytes = null;
        } finally {
          _inFlight.remove(id);
        }
        if (bytes != null && bytes.isNotEmpty && generation == _generation) {
          _cache[id] = bytes;
          _ready.add(id);
        } else if (generation == _generation) {
          // Remember the failure so the tile's re-request does not retry it
          // endlessly. A generation change means the vault relocked mid-read, so
          // the id is NOT poisoned for the next unlock.
          _unavailable.add(id);
        }
      }
    } finally {
      _draining = false;
    }
  }
}

/// The production resolver. Legacy blobs answer null — a thumbnail must NEVER
/// trigger the F20/H8 migration as a side effect (`ensureVideoStreamable` would
/// run a full decrypt/re-encrypt just to draw a tile), so the format is checked
/// first. c2 blobs stream through the vault's own loopback server.
Future<Uri?> resolveThumbnailStreamUrl(VideoVaultService vault, String id) async {
  if (!await vault.isCtrV2Blob(id)) return null;
  final (uri, _) = await MediaStreamServer.instance.streamableUrlFor(id);
  return uri;
}

/// Reactive view of the cache: a grid tile watches this map and rebuilds the
/// moment its frame lands.
class VideoThumbnailCacheNotifier
    extends StateNotifier<Map<String, Uint8List>> {
  VideoThumbnailCacheNotifier(this._service)
      : super(const <String, Uint8List>{}) {
    _sub = _service.onReady.listen((id) {
      final bytes = _service.cachedFor(id);
      if (bytes != null) {
        state = <String, Uint8List>{...state, id: bytes};
      }
    });
  }

  final VideoThumbnailService _service;
  late final StreamSubscription<String> _sub;

  /// Lock path: wipe the backing store and the exposed map together.
  void wipe() {
    _service.clear();
    state = const <String, Uint8List>{};
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) {
  final vault = ref.watch(videoVaultServiceProvider);
  return VideoThumbnailService(
    resolveStreamUrl: (id) => resolveThumbnailStreamUrl(vault, id),
  );
});

final videoThumbnailCacheProvider =
    StateNotifierProvider<VideoThumbnailCacheNotifier, Map<String, Uint8List>>(
  (ref) => VideoThumbnailCacheNotifier(ref.watch(videoThumbnailServiceProvider)),
);
