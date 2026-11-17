import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/crypto_isolate.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/security/pin_wipe_service.dart';
import 'package:mimic/vault/security/vault_ui_access.dart';
import 'package:mimic/vault/services/background_import_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/import_coordinator.dart';
import 'package:mimic/vault/services/import_journal_store.dart';
import 'package:mimic/vault/services/import_progress.dart';
import 'package:mimic/vault/services/media_import_policy.dart';
import 'package:mimic/vault/services/media_picker_adapter.dart';
import 'package:mimic/vault/services/notes_service.dart';
import 'package:mimic/vault/services/orphan_detection_service.dart';
import 'package:mimic/vault/services/vault_media_commit_helper.dart';
import 'package:mimic/vault/services/vault_wipe_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';

class _TestPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;
  final String tempPath;

  _TestPathProvider({required this.docsPath, required this.tempPath});

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

class _PassThroughKeystore implements KeystoreService {
  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async => base64Data;

  @override
  Future<String> unwrap(String base64Data) async => base64Data;

  @override
  Future<void> deleteKey() async {}
}

/// Real AES-256-CTR/HMAC-SHA256 (`MVKEYc3\0`) + AES-256-GCM test VaultCrypto
/// without 600,000-round KDF startup delay, so every single file encrypts via
/// the production background isolate worker and validates real MAC tags.
class _HarnessCrypto extends Fake with ChangeNotifier implements VaultCrypto {
  final List<void Function(int newEpoch)> _beforeLockListeners = [];
  final Random _rand = Random.secure();

  bool _unlocked = false;
  int _lockEpoch = 0;
  Uint8List? _key;

  @override
  bool get isUnlocked => _unlocked;

  @override
  int get lockEpoch => _lockEpoch;

  void unlockWithKey(Uint8List rawKey) {
    _key?.fillRange(0, _key!.length, 0);
    _key = Uint8List.fromList(rawKey);
    _unlocked = true;
    notifyListeners();
  }

  @override
  void Function() addBeforeLockListener(void Function(int newEpoch) listener) {
    _beforeLockListeners.add(listener);
    return () => _beforeLockListeners.remove(listener);
  }

  @override
  void lock() {
    _unlocked = false;
    _lockEpoch++;
    for (final l in List<void Function(int)>.from(_beforeLockListeners)) {
      try {
        l(_lockEpoch);
      } catch (_) {}
    }
    final oldKey = _key;
    _key = null;
    if (oldKey != null) {
      oldKey.fillRange(0, oldKey.length, 0);
    }
    scheduleMicrotask(() {
      notifyListeners();
    });
  }

  @override
  void clearKey() => lock();

  Uint8List _randomBytes(int len) =>
      Uint8List.fromList(List<int>.generate(len, (_) => _rand.nextInt(256)));

  @override
  String encryptString(String plaintext) {
    final key = _key;
    if (!_unlocked || key == null) throw Exception('Vault is locked');
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final pt = Uint8List.fromList(utf8.encode(plaintext));
    final out = cipher.process(pt);
    final combined = Uint8List(nonce.length + out.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + out.length, out);
    return base64Encode(combined);
  }

  @override
  String decryptString(String ciphertext) {
    final key = _key;
    if (!_unlocked || key == null) throw Exception('Vault is locked');
    final raw = base64Decode(ciphertext);
    if (raw.length < 28) throw Exception('Invalid ciphertext');
    final nonce = raw.sublist(0, 12);
    final body = raw.sublist(12);
    final cipher = GCMBlockCipher(
      AESEngine(),
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return utf8.decode(cipher.process(body));
  }

  @override
  Future<void> encryptStreamSystemCtrV3(File src, File dest) =>
      encryptStreamSystemCtrV3Controlled(src, dest);

  @override
  Future<void> encryptStreamSystemCtrV3Controlled(
    File src,
    File dest, {
    bool Function()? shouldAbort,
    CryptoIsolateCancelHandle? cancelHandle,
    void Function(int bytesProcessed)? onBytesProgress,
  }) async {
    final key = _key;
    if (!_unlocked || key == null) throw Exception('Vault is locked');
    final iv = _randomBytes(16);
    await cryptoIsolateEncryptFileCtr(
      key: Uint8List.fromList(key),
      iv: iv,
      srcPath: src.path,
      destPath: dest.path,
      writeC3: true,
      shouldAbort: shouldAbort,
      cancelHandle: cancelHandle,
      onBytesProgress: onBytesProgress,
    );
  }

  @override
  Future<Uint8List> decryptSystem(Uint8List encrypted) async {
    final key = _key;
    if (!_unlocked || key == null) throw Exception('Vault is locked');
    final iv = encrypted.sublist(kAuthIvOffset, kAuthTagOffset);
    final ciphertext = authenticateBlob(
      blob: encrypted,
      macKey: deriveMacKey(key),
    );
    final aes = AESEngine()..init(true, KeyParameter(key));
    final counter = Uint8List.fromList(iv);
    final ks = Uint8List(16);
    final out = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      aes.processBlock(counter, 0, ks, 0);
      final chunk = (ciphertext.length - offset) < 16
          ? (ciphertext.length - offset)
          : 16;
      for (var i = 0; i < chunk; i++) {
        out[offset + i] = ciphertext[offset + i] ^ ks[i];
      }
      for (var i = 15; i >= 0; i--) {
        counter[i] = (counter[i] + 1) & 0xFF;
        if (counter[i] != 0) break;
      }
      offset += chunk;
    }
    return out;
  }

  @override
  Future<Uint8List?> tryDecryptFileInWorker(File file) async => null;

  @override
  bool isLegacySystemBlob(Uint8List blob) => false;

  @override
  Future<BlobIntegrityStatus> verifyFileIntegrity(File file) async {
    if (!await file.exists()) return BlobIntegrityStatus.fileNotFound;
    final bytes = await file.readAsBytes();
    if (bytes.length < kAuthHeaderLength) {
      return BlobIntegrityStatus.fileTooShort;
    }
    if (classifyMediaHeader(bytes.sublist(0, 8)) != MediaBlobFormat.ctrV3) {
      return BlobIntegrityStatus.tamperedOrCorrupted;
    }
    final key = _key;
    if (!_unlocked || key == null) return BlobIntegrityStatus.vaultLocked;
    try {
      authenticateBlob(blob: bytes, macKey: deriveMacKey(key));
      return BlobIntegrityStatus.healthy;
    } on BlobAuthenticationException {
      return BlobIntegrityStatus.tamperedOrCorrupted;
    }
  }
}

class _ControlledGalleryAsset {
  final String id;
  final ImportMediaKind kind;
  final String name;
  final String mimeType;
  final int durationS;
  final File file;
  MediaSourceResolutionStatus? forcedFailureStatus;
  bool deleteConfirmed = true;
  bool throwUnreadableHash = false;

  _ControlledGalleryAsset({
    required this.id,
    required this.kind,
    required this.name,
    required this.mimeType,
    this.durationS = 0,
    required this.file,
    this.forcedFailureStatus,
    this.deleteConfirmed = true,
  });

  MediaSourceRef toRef() => MediaSourceRef(
    sourceAssetId: id,
    kind: kind,
    displayName: name,
    mimeType: mimeType,
    durationSeconds: durationS,
    expectedSizeBytes: file.existsSync() ? file.lengthSync() : 0,
  );
}

class _ControllablePickerAdapter implements MediaPickerAdapter {
  PermissionState permissionState = PermissionState.authorized;
  final Map<String, _ControlledGalleryAsset> assets = {};
  final List<List<String>> deleteRequests = [];
  bool throwDeletePermissionDenied = false;

  void addAsset(_ControlledGalleryAsset asset) {
    assets[asset.id] = asset;
  }

  @override
  Future<PermissionState> requestPermission(ImportMediaKind kind) async {
    return permissionState;
  }

  @override
  Future<List<MediaSourceRef>?> pickAssets(
    BuildContext context, {
    required ImportMediaKind kind,
    int maxAssets = kMaxMediaImportSelection,
  }) async {
    return assets.values
        .where((a) => a.kind == kind)
        .take(maxAssets)
        .map((a) => a.toRef())
        .toList();
  }

  @override
  Future<ResolvedMediaSource> resolveSource(MediaSourceRef ref) async {
    if (!permissionState.hasAccess) {
      return ResolvedMediaSource.unavailable(
        status: MediaSourceResolutionStatus.permissionDenied,
        mimeType: ref.mimeType,
        displayName: ref.displayName,
        errorCode: 'permission_denied',
        safeReason: 'Gallery permission revoked',
      );
    }
    final asset = assets[ref.sourceAssetId];
    if (asset == null) {
      return ResolvedMediaSource.unavailable(
        status: MediaSourceResolutionStatus.missing,
        mimeType: ref.mimeType,
        displayName: ref.displayName,
        errorCode: 'source_missing',
        safeReason: 'Original media item removed',
      );
    }
    if (asset.forcedFailureStatus != null) {
      return ResolvedMediaSource.unavailable(
        status: asset.forcedFailureStatus!,
        mimeType: asset.mimeType,
        displayName: asset.name,
        errorCode: asset.forcedFailureStatus!.name,
        safeReason: 'Forced failure ${asset.forcedFailureStatus!.name}',
      );
    }
    if (!asset.file.existsSync()) {
      return ResolvedMediaSource.unavailable(
        status: MediaSourceResolutionStatus.missing,
        mimeType: asset.mimeType,
        displayName: asset.name,
        errorCode: 'source_missing',
        safeReason: 'Source file deleted from disk',
      );
    }
    if (asset.throwUnreadableHash) {
      return ResolvedMediaSource.ready(
        localFilePath: p.join(
          asset.file.parent.path,
          'missing_after_resolve.bin',
        ),
        mimeType: asset.mimeType,
        displayName: asset.name,
        durationSeconds: asset.durationS,
        sizeBytes: 128,
      );
    }
    return ResolvedMediaSource.ready(
      localFilePath: asset.file.path,
      mimeType: asset.mimeType,
      displayName: asset.name,
      durationSeconds: asset.durationS,
      sizeBytes: asset.file.lengthSync(),
    );
  }

  @override
  Future<MediaDeleteResult> deleteOriginals(List<String> assetIds) async {
    deleteRequests.add(List<String>.from(assetIds));
    if (throwDeletePermissionDenied || !permissionState.hasAccess) {
      return MediaDeleteResult(
        deletedIds: const <String>{},
        keptIds: assetIds.toSet(),
        permissionDenied: true,
        errorCode: 'delete_permission_denied',
      );
    }
    final deleted = <String>{};
    final kept = <String>{};
    for (final id in assetIds) {
      final asset = assets[id];
      if (asset != null && asset.deleteConfirmed) {
        deleted.add(id);
        if (asset.file.existsSync()) {
          asset.file.deleteSync();
        }
      } else {
        kept.add(id);
      }
    }
    return MediaDeleteResult(deletedIds: deleted, keptIds: kept);
  }
}

/// Fault-injectable journal wrapper used to verify database-failure pause semantics.
class _FaultyJournalStore extends ImportJournalStore {
  bool failNextInsert = false;
  bool failNextLoad = false;

  _FaultyJournalStore(super.crypto);

  @override
  Future<void> insertBatch(List<DurableImportJob> jobs) async {
    if (failNextInsert) {
      throw const ImportJournalException(
        ImportJournalErrorKind.storageOrDbFailure,
        'Simulated SQLite write error',
      );
    }
    return super.insertBatch(jobs);
  }

  @override
  Future<({List<DurableImportJob> jobs, int undecryptableCount})>
  loadDecryptedJobs() async {
    if (failNextLoad) {
      throw const ImportJournalException(
        ImportJournalErrorKind.corrupt,
        'Simulated corrupt journal DB',
      );
    }
    return super.loadDecryptedJobs();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory docsDir;
  late Directory tempDir;
  late Directory dbDir;
  late Directory sourceDir;
  late PathProviderPlatform originalPathProvider;
  late String originalDbPath;

  final Uint8List masterKeyA = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 13 + 7) & 0xFF),
  );
  final Uint8List masterKeyB = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 29 + 3) & 0xFF),
  );

  final Map<String, String> secureStoreData = {};
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalPathProvider = PathProviderPlatform.instance;
    originalDbPath = await getDatabasesPath();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'pro_offers_enabled': false});
    secureStoreData.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          switch (call.method) {
            case 'read':
              return secureStoreData[call.arguments['key'] as String];
            case 'readAll':
              return Map<String, String>.from(secureStoreData);
            case 'write':
              final key = call.arguments['key'] as String;
              final value = call.arguments['value'] as String?;
              if (value == null) {
                secureStoreData.remove(key);
              } else {
                secureStoreData[key] = value;
              }
              return null;
            case 'delete':
              secureStoreData.remove(call.arguments['key'] as String);
              return null;
            case 'deleteAll':
              secureStoreData.clear();
              return null;
            default:
              return null;
          }
        });
    tempRoot = await Directory.systemTemp.createTemp('mimic_import_reg_');
    docsDir = Directory(p.join(tempRoot.path, 'docs'))..createSync();
    tempDir = Directory(p.join(tempRoot.path, 'temp'))..createSync();
    dbDir = Directory(p.join(tempRoot.path, 'dbs'))..createSync();
    sourceDir = Directory(p.join(tempRoot.path, 'gallery'))..createSync();

    PathProviderPlatform.instance = _TestPathProvider(
      docsPath: docsDir.path,
      tempPath: tempDir.path,
    );
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  tearDown(() async {
    AutoLock().dispose();
    await databaseFactory.setDatabasesPath(originalDbPath);
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) {
      for (var i = 0; i < 5; i++) {
        try {
          tempRoot.deleteSync(recursive: true);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
    }
  });

  Uint8List deterministicPayload(int seed, int length) {
    final rand = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rand.nextInt(256)),
    );
  }

  File writeGalleryFile(String name, Uint8List bytes) {
    final file = File(p.join(sourceDir.path, name));
    file.writeAsBytesSync(bytes);
    return file;
  }

  Future<
    ({
      AndroidPlatformService platform,
      _HarnessCrypto crypto,
      FileVaultService fileVault,
      VideoVaultService videoVault,
      _ControllablePickerAdapter picker,
      ImportJournalStore journal,
      ImportCoordinator coordinator,
      void Function(int?) setAvailableBytes,
    })
  >
  buildEnv({
    ImportCoordinatorStageHooks? stageHooks,
    ImportJournalStore? customJournal,
    int? initialAvailableBytes = 1024 * 1024 * 1024,
  }) async {
    int? avail = initialAvailableBytes;
    final platform = AndroidPlatformService();
    final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
    final fileVault = FileVaultService(platform, crypto);
    final videoVault = VideoVaultService(platform, crypto);
    final picker = _ControllablePickerAdapter();
    final journal = customJournal ?? ImportJournalStore(crypto);
    final coordinator = ImportCoordinator(
      crypto: crypto,
      platformService: platform,
      fileVault: fileVault,
      videoVault: videoVault,
      pickerAdapter: picker,
      journal: journal,
      storageProbe: () async => avail,
      stageHooks: stageHooks,
    );
    return (
      platform: platform,
      crypto: crypto,
      fileVault: fileVault,
      videoVault: videoVault,
      picker: picker,
      journal: journal,
      coordinator: coordinator,
      setAvailableBytes: (int? v) => avail = v,
    );
  }

  Future<void> disposeEnv({
    required ImportCoordinator coordinator,
    required FileVaultService fileVault,
    required VideoVaultService videoVault,
    required ImportJournalStore journal,
  }) async {
    coordinator.dispose();
    await journal.close();
    await fileVault.closeDatabase();
    await videoVault.closeDatabase();
  }

  Future<void> waitUntilSettled(ImportCoordinator coordinator) {
    if (!coordinator.isWorking) return Future.value();
    final c = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (!coordinator.isWorking && !c.isCompleted) {
        coordinator.removeListener(listener);
        c.complete();
      }
    };
    coordinator.addListener(listener);
    return c.future;
  }

  Future<void> waitUntil(bool Function() predicate, Listenable listenable) {
    if (predicate()) return Future.value();
    final c = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (predicate() && !c.isCompleted) {
        listenable.removeListener(listener);
        c.complete();
      }
    };
    listenable.addListener(listener);
    return c.future;
  }

  group('1 · Shared Picker Policy and Scale (10, 25, 100 items)', () {
    test(
      'buildPickerConfig explicitly sets maxAssets = 100 for photos and videos',
      () {
        final photoCfg = MediaImportPolicy.buildPickerConfig(
          ImportMediaKind.photo,
        );
        final videoCfg = MediaImportPolicy.buildPickerConfig(
          ImportMediaKind.video,
        );

        expect(MediaImportPolicy.maxAssetsPerBatch, 100);
        expect(photoCfg.maxAssets, 100);
        expect(photoCfg.requestType, RequestType.image);
        expect(videoCfg.maxAssets, 100);
        expect(videoCfg.requestType, RequestType.video);
        expect(kMediaImportLimitBanner, contains('100'));
      },
    );

    for (final count in [10, 25, 100]) {
      test(
        'imports $count mixed assets serially with zero duplicates, zero orphans, and authentic decryptability',
        () async {
          final env = await buildEnv();
          final expectedPlaintextByName = <String, Uint8List>{};
          final sources = <MediaSourceRef>[];
          var activeCount = 0;
          var maxConcurrent = 0;

          final hookCoordinator = ImportCoordinator(
            crypto: env.crypto,
            platformService: env.platform,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            pickerAdapter: env.picker,
            journal: env.journal,
            storageProbe: () async => 2 * 1024 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                activeCount++;
                if (activeCount > maxConcurrent) maxConcurrent = activeCount;
              },
              onBeforeCommitMeta: (_) async {
                activeCount--;
              },
            ),
          );
          env.coordinator.dispose();

          try {
            for (var i = 0; i < count; i++) {
              final isVideo = i % 5 == 0;
              final name = isVideo ? 'vid_$i.mp4' : 'img_$i.jpg';
              final bytes = deterministicPayload(i + 100, 1024 + (i % 7) * 256);
              expectedPlaintextByName[name] = bytes;
              final asset = _ControlledGalleryAsset(
                id: 'asset_$i',
                kind: isVideo ? ImportMediaKind.video : ImportMediaKind.photo,
                name: name,
                mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
                durationS: isVideo ? 4 : 0,
                file: writeGalleryFile(name, bytes),
              );
              env.picker.addAsset(asset);
              sources.add(asset.toRef());
            }

            await hookCoordinator.enqueueBatch(
              sources: sources,
              scope: const VaultImportScope(),
            );
            await waitUntilSettled(hookCoordinator);

            expect(maxConcurrent, 1, reason: 'Serial single worker invariant');

            final savedPhotos = await env.fileVault.getAllPhotos();
            final savedVideos = await env.videoVault.getAllVideos();
            expect(savedPhotos.length + savedVideos.length, count);
            expect(
              savedPhotos.map((e) => e.id).toSet().length +
                  savedVideos.map((e) => e.id).toSet().length,
              count,
            );

            // Sample spot-check & full count/integrity verification
            for (final pMeta in savedPhotos) {
              expect(
                await env.fileVault.verifyCommittedPhotoBlob(pMeta.id),
                BlobIntegrityStatus.healthy,
              );
              final decrypted = await env.fileVault.getPhoto(pMeta.id);
              expect(decrypted, expectedPlaintextByName[pMeta.originalName]);
            }
            for (final vMeta in savedVideos) {
              expect(
                await env.videoVault.verifyCommittedVideoBlob(vMeta.id),
                BlobIntegrityStatus.healthy,
              );
              final decrypted = await env.videoVault.getVideo(vMeta.id);
              expect(decrypted, expectedPlaintextByName[vMeta.originalName]);
            }

            // Zero orphan blobs and zero leftover .part files
            final orphanScan = await OrphanDetectionService(
              env.platform,
              env.fileVault,
              env.videoVault,
              DocumentVaultService(env.platform, env.crypto),
            ).scanOrphans(tempGracePeriod: Duration.zero);
            expect(orphanScan.hasOrphans, isFalse);

            final stagingDir = Directory(
              p.join(docsDir.path, 'vault_files', kImportStagingDirName),
            );
            if (stagingDir.existsSync()) {
              expect(stagingDir.listSync().whereType<File>(), isEmpty);
            }

            // Originals untouched because no foreground delete confirmation ran
            for (final a in env.picker.assets.values) {
              expect(a.file.existsSync(), isTrue);
            }
            expect(
              hookCoordinator.jobs.every(
                (j) =>
                    j.state == ImportJobState.awaitingDeleteConfirmation ||
                    j.state == ImportJobState.savedOriginalKept,
              ),
              isTrue,
            );
            expect(AutoLock().protectedOperationCount, 0);
            expect(AutoLock().hasActiveImportAuthorization, isFalse);
            expect(hookCoordinator.hasActiveImportLeaseForTest, isFalse);
            expect(AutoLock().isSuspended, isFalse);
          } finally {
            await disposeEnv(
              coordinator: hookCoordinator,
              fileVault: env.fileVault,
              videoVault: env.videoVault,
              journal: env.journal,
            );
          }
        },
        timeout: count >= 100 ? const Timeout(Duration(minutes: 3)) : null,
      );
    }

    test(
      'appending a video batch while photo batch is mid-flight preserves order without overwrite',
      () async {
        final encryptGate = Completer<void>();
        final enteredEncrypt = Completer<void>();
        late final ImportCoordinator coordinator;

        final platform = AndroidPlatformService();
        final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
        final fileVault = FileVaultService(platform, crypto);
        final videoVault = VideoVaultService(platform, crypto);
        final picker = _ControllablePickerAdapter();
        final journal = ImportJournalStore(crypto);
        coordinator = ImportCoordinator(
          crypto: crypto,
          platformService: platform,
          fileVault: fileVault,
          videoVault: videoVault,
          pickerAdapter: picker,
          journal: journal,
          storageProbe: () async => 500 * 1024 * 1024,
          stageHooks: ImportCoordinatorStageHooks(
            onBeforeEncrypt: (job) async {
              if (job.payload.displayName == 'p1.jpg') {
                if (!enteredEncrypt.isCompleted) enteredEncrypt.complete();
                await encryptGate.future;
              }
            },
          ),
        );

        try {
          final p1 = _ControlledGalleryAsset(
            id: 'p1',
            kind: ImportMediaKind.photo,
            name: 'p1.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('p1.jpg', deterministicPayload(1, 2048)),
          );
          final v1 = _ControlledGalleryAsset(
            id: 'v1',
            kind: ImportMediaKind.video,
            name: 'v1.mp4',
            mimeType: 'video/mp4',
            durationS: 3,
            file: writeGalleryFile('v1.mp4', deterministicPayload(2, 4096)),
          );
          picker.addAsset(p1);
          picker.addAsset(v1);

          final batch1 = await coordinator.enqueueBatch(
            sources: [p1.toRef()],
            scope: const VaultImportScope(),
          );
          await enteredEncrypt.future;

          final batch2 = await coordinator.enqueueBatch(
            sources: [v1.toRef()],
            scope: const VaultImportScope(),
          );
          expect(batch1, isNotNull);
          expect(batch2, isNot(equals(batch1)));
          expect(coordinator.jobs.length, 2);
          expect(coordinator.jobs[0].state, ImportJobState.encrypting);
          expect(coordinator.jobs[1].state, ImportJobState.queued);

          encryptGate.complete();
          await waitUntilSettled(coordinator);

          expect((await fileVault.getAllPhotos()).length, 1);
          expect((await videoVault.getAllVideos()).length, 1);
        } finally {
          await disposeEnv(
            coordinator: coordinator,
            fileVault: fileVault,
            videoVault: videoVault,
            journal: journal,
          );
        }
      },
    );
  });

  group('2 · Lock Boundaries, Isolate Cancellation & Epoch Fencing', () {
    test(
      'real cryptoIsolateEncryptFileCtr aborts on cancelHandle, zeroes buffers, and removes staging file',
      () async {
        final largePlain = deterministicPayload(42, 4 * 1024 * 1024);
        final src = writeGalleryFile('large_video.mp4', largePlain);
        final staging = File(p.join(docsDir.path, 'large_stage.part'));
        final iv = Uint8List.fromList(List<int>.generate(16, (i) => i));
        final cancelHandle = CryptoIsolateCancelHandle();
        final progressPort = ReceivePort();
        final firstChunkSeen = Completer<void>();

        final sub = progressPort.listen((_) {
          if (!firstChunkSeen.isCompleted) firstChunkSeen.complete();
        });

        final encryptFuture = cryptoIsolateEncryptFileCtr(
          key: masterKeyA,
          iv: iv,
          srcPath: src.path,
          destPath: staging.path,
          progressPort: progressPort.sendPort,
          writeC3: true,
          cancelHandle: cancelHandle,
        );

        await firstChunkSeen.future;
        await cancelHandle.abort();

        await expectLater(
          encryptFuture,
          throwsA(isA<OperationCancelledException>()),
        );
        expect(staging.existsSync(), isFalse);
        await sub.cancel();
        progressPort.close();
      },
    );

    for (final boundary in [
      'resolve',
      'hash',
      'encrypt',
      'afterEncrypt',
      'publish',
      'meta',
    ]) {
      test(
        'vault lock during $boundary boundary pauses cleanly with zero orphan blobs and released lease',
        () async {
          final boundaryReached = Completer<void>();
          final releaseGate = Completer<void>();
          late final _HarnessCrypto crypto;
          late final ImportCoordinator coordinator;

          final platform = AndroidPlatformService();
          crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final videoVault = VideoVaultService(platform, crypto);
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);

          ImportCoordinatorStageHooks buildHooks() {
            Future<void> triggerLock(DurableImportJob _) async {
              if (!boundaryReached.isCompleted) boundaryReached.complete();
              await releaseGate.future;
            }

            return ImportCoordinatorStageHooks(
              onBeforeResolve: boundary == 'resolve' ? triggerLock : null,
              onBeforeHash: boundary == 'hash' ? triggerLock : null,
              onBeforeEncrypt: boundary == 'encrypt' ? triggerLock : null,
              onAfterEncryptBeforeVerify: boundary == 'afterEncrypt'
                  ? triggerLock
                  : null,
              onBeforeCommitPublish: boundary == 'publish' ? triggerLock : null,
              onBeforeCommitMeta: boundary == 'meta' ? triggerLock : null,
            );
          }

          coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: buildHooks(),
          );

          try {
            final a1 = _ControlledGalleryAsset(
              id: 'a1',
              kind: ImportMediaKind.photo,
              name: 'photo_a1.jpg',
              mimeType: 'image/jpeg',
              file: writeGalleryFile(
                'photo_a1.jpg',
                deterministicPayload(9, 4096),
              ),
            );
            final a2 = _ControlledGalleryAsset(
              id: 'a2',
              kind: ImportMediaKind.video,
              name: 'video_a2.mp4',
              mimeType: 'video/mp4',
              durationS: 5,
              file: writeGalleryFile(
                'video_a2.mp4',
                deterministicPayload(10, 4096),
              ),
            );
            picker
              ..addAsset(a1)
              ..addAsset(a2);

            await coordinator.enqueueBatch(
              sources: [a1.toRef(), a2.toRef()],
              scope: const VaultImportScope(),
            );
            await boundaryReached.future;

            crypto.lock();
            expect(crypto.isUnlocked, isFalse);
            expect(coordinator.isWorking, isFalse);
            expect(AutoLock().protectedOperationCount, 0);

            releaseGate.complete();
            await waitUntil(() => !coordinator.isWorking, coordinator);

            // Re-unlock with no hooks barrier and resume remaining jobs cleanly
            crypto.unlockWithKey(masterKeyA);
            // Bypass barrier on resume so second run completes cleanly
            final resumedCoordinator = ImportCoordinator(
              crypto: crypto,
              platformService: platform,
              fileVault: fileVault,
              videoVault: videoVault,
              pickerAdapter: picker,
              journal: ImportJournalStore(crypto),
              storageProbe: () async => 500 * 1024 * 1024,
            );
            coordinator.dispose();

            await resumedCoordinator.syncAfterUnlock();
            await waitUntilSettled(resumedCoordinator);

            expect((await fileVault.getAllPhotos()).length, 1);
            expect((await videoVault.getAllVideos()).length, 1);

            final orphanScan = await OrphanDetectionService(
              platform,
              fileVault,
              videoVault,
              DocumentVaultService(platform, crypto),
            ).scanOrphans(tempGracePeriod: Duration.zero);
            expect(orphanScan.hasOrphans, isFalse);
            resumedCoordinator.dispose();
          } finally {
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
            await journal.close();
          }
        },
      );
    }

    test(
      'rejects stale worker completion after lock -> relock -> unlock across epochs',
      () async {
        final workerBlocked = Completer<void>();
        final workerRelease = Completer<void>();
        var blockOnce = true;

        final platform = AndroidPlatformService();
        final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
        final fileVault = FileVaultService(platform, crypto);
        final videoVault = VideoVaultService(platform, crypto);
        final picker = _ControllablePickerAdapter();
        final journal = ImportJournalStore(crypto);
        final coordinator = ImportCoordinator(
          crypto: crypto,
          platformService: platform,
          fileVault: fileVault,
          videoVault: videoVault,
          pickerAdapter: picker,
          journal: journal,
          storageProbe: () async => 500 * 1024 * 1024,
          stageHooks: ImportCoordinatorStageHooks(
            onAfterEncryptBeforeVerify: (job) async {
              if (blockOnce) {
                blockOnce = false;
                workerBlocked.complete();
                await workerRelease.future;
              }
            },
          ),
        );

        try {
          final a1 = _ControlledGalleryAsset(
            id: 'stale1',
            kind: ImportMediaKind.photo,
            name: 'stale.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('stale.jpg', deterministicPayload(33, 2048)),
          );
          picker.addAsset(a1);

          await coordinator.enqueueBatch(
            sources: [a1.toRef()],
            scope: const VaultImportScope(),
          );
          await workerBlocked.future;

          // Lock then immediately unlock -> starts session 2 while session 1 is still parked on workerRelease!
          crypto.lock();
          crypto.unlockWithKey(masterKeyA);
          await waitUntilSettled(coordinator);
          expect((await fileVault.getAllPhotos()).length, 1);

          // Now release old session 1 continuation: it must be rejected without corrupting session 2!
          final staleDone = waitUntil(
            () => coordinator.rejectedStaleCompletionCount >= 1,
            coordinator,
          );
          workerRelease.complete();
          await staleDone.timeout(const Duration(seconds: 5));

          expect(
            coordinator.rejectedStaleCompletionCount,
            greaterThanOrEqualTo(1),
          );
          expect((await fileVault.getAllPhotos()).length, 1);
        } finally {
          await disposeEnv(
            coordinator: coordinator,
            fileVault: fileVault,
            videoVault: videoVault,
            journal: journal,
          );
        }
      },
    );

    test(
      'explicit cancellation stops remaining items cleanly and is NOT auto-retried on unlock',
      () async {
        final env = await buildEnv();
        final barrierHit = Completer<void>();
        final barrierRelease = Completer<void>();

        final hooked = ImportCoordinator(
          crypto: env.crypto,
          platformService: env.platform,
          fileVault: env.fileVault,
          videoVault: env.videoVault,
          pickerAdapter: env.picker,
          journal: env.journal,
          storageProbe: () async => 500 * 1024 * 1024,
          stageHooks: ImportCoordinatorStageHooks(
            onBeforeEncrypt: (job) async {
              if (job.payload.displayName == 'c1.jpg' &&
                  !barrierHit.isCompleted) {
                barrierHit.complete();
                await barrierRelease.future;
              }
            },
          ),
        );
        env.coordinator.dispose();

        try {
          final a1 = _ControlledGalleryAsset(
            id: 'c1',
            kind: ImportMediaKind.photo,
            name: 'c1.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('c1.jpg', deterministicPayload(71, 1024)),
          );
          final a2 = _ControlledGalleryAsset(
            id: 'c2',
            kind: ImportMediaKind.photo,
            name: 'c2.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('c2.jpg', deterministicPayload(72, 1024)),
          );
          env.picker
            ..addAsset(a1)
            ..addAsset(a2);

          await hooked.enqueueBatch(
            sources: [a1.toRef(), a2.toRef()],
            scope: const VaultImportScope(),
          );
          await barrierHit.future;

          final cancelFuture = hooked.cancelActive();
          barrierRelease.complete();
          await cancelFuture;
          await waitUntilSettled(hooked);

          expect(
            hooked.jobs.every((j) => j.state == ImportJobState.cancelled),
            isTrue,
          );
          expect(await env.fileVault.getAllPhotos(), isEmpty);

          // Lock then unlock: cancelled jobs MUST stay cancelled!
          env.crypto.lock();
          env.crypto.unlockWithKey(masterKeyA);
          await hooked.syncAfterUnlock();
          await waitUntilSettled(hooked);

          expect(
            hooked.jobs.every((j) => j.state == ImportJobState.cancelled),
            isTrue,
          );
          expect(await env.fileVault.getAllPhotos(), isEmpty);
        } finally {
          await disposeEnv(
            coordinator: hooked,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            journal: env.journal,
          );
        }
      },
    );
  });

  group('3 · Real KDF Restart Recovery, Crash Reconciliation & Privacy', () {
    test(
      'reconciles interrupted encrypt, post-rename crash, post-DB crash, and orphan blobs across real VaultCrypto restart',
      () async {
        final platform = AndroidPlatformService();
        final keystore = _PassThroughKeystore();
        final picker = _ControllablePickerAdapter();

        final p1Bytes = deterministicPayload(201, 2048);
        final p2Bytes = deterministicPayload(202, 2048);
        final p3Bytes = deterministicPayload(203, 2048);
        final p4Bytes = deterministicPayload(204, 2048);

        final a1 = _ControlledGalleryAsset(
          id: 'rec_done_id_secret',
          kind: ImportMediaKind.photo,
          name: 'already_done_secret.jpg',
          mimeType: 'image/jpeg',
          file: writeGalleryFile('already_done_secret.jpg', p1Bytes),
        );
        final a2 = _ControlledGalleryAsset(
          id: 'rec_post_rename_id',
          kind: ImportMediaKind.photo,
          name: 'crashed_after_rename.jpg',
          mimeType: 'image/jpeg',
          file: writeGalleryFile('crashed_after_rename.jpg', p2Bytes),
        );
        final a3 = _ControlledGalleryAsset(
          id: 'rec_orphan_id',
          kind: ImportMediaKind.photo,
          name: 'orphan_pre_commit.jpg',
          mimeType: 'image/jpeg',
          file: writeGalleryFile('orphan_pre_commit.jpg', p3Bytes),
        );
        final a4 = _ControlledGalleryAsset(
          id: 'rec_interrupted_id',
          kind: ImportMediaKind.video,
          name: 'interrupted_clip.mp4',
          mimeType: 'video/mp4',
          durationS: 7,
          file: writeGalleryFile('interrupted_clip.mp4', p4Bytes),
        );
        picker
          ..addAsset(a1)
          ..addAsset(a2)
          ..addAsset(a3)
          ..addAsset(a4);

        // Process 1: real PBKDF2 VaultCrypto initialize('1234')
        final crypto1 = VaultCrypto(platform, keystore);
        await crypto1.initialize('1234');
        final fv1 = FileVaultService(platform, crypto1);
        final vv1 = VideoVaultService(platform, crypto1);
        final journal1 = ImportJournalStore(crypto1);

        // Simulate state left on disk at process death across 4 crash boundaries:
        const dest1 = 'dest-uuid-0001';
        const dest2 = 'dest-uuid-0002';
        const dest3 = 'dest-uuid-0003';
        const dest4 = 'dest-uuid-0004';

        // Boundary 1: a1 already committed BOTH DB + authenticated blob, journal still says `committing`
        final stage1 = await fv1.prepareImportStagingFile(dest1);
        await fv1.encryptPhotoToStaging(
          sourceFile: a1.file,
          stagingFile: stage1,
        );
        await fv1.commitStagedPhoto(
          id: dest1,
          stagingFile: stage1,
          mimeType: 'image/jpeg',
          plaintextSize: p1Bytes.length,
          originalName: a1.name,
          contentHash: PhotoMeta.computeHash(p1Bytes),
        );

        // Boundary 2: a2 renamed atomically to vault_files/dest2 BEFORE DB metadata insert while journal was `committing`
        final blob2Dest = await platform.resolveVaultFile(dest2);
        await crypto1.encryptStreamSystemCtrV3(a2.file, blob2Dest);

        // Boundary 3: a3 left an ambiguous partial/unauthenticated garbage blob at dest3 while journal was `encrypting`
        final blob3Dest = await platform.resolveVaultFile(dest3);
        await blob3Dest.writeAsBytes([1, 2, 3, 4, 5, 6, 7]);

        // Boundary 4: a4 left a partial `.part` staging file inside `.import_staging` while `encrypting`
        final stage4 = await vv1.prepareImportStagingFile(dest4);
        await stage4.writeAsBytes([9, 8, 7]);

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await journal1.insertBatch([
          DurableImportJob(
            jobId: 'j1',
            batchId: 'b1',
            destId: dest1,
            enqueueOrder: 1,
            mediaKind: ImportMediaKind.photo,
            scope: const VaultImportScope(),
            state: ImportJobState.committing,
            attemptCount: 1,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            payload: ImportJobSensitivePayload(
              sourceAssetId: a1.id,
              displayName: a1.name,
              mimeType: 'image/jpeg',
              expectedSizeBytes: p1Bytes.length,
              contentHash: PhotoMeta.computeHash(p1Bytes),
            ),
          ),
          DurableImportJob(
            jobId: 'j2',
            batchId: 'b1',
            destId: dest2,
            enqueueOrder: 2,
            mediaKind: ImportMediaKind.photo,
            scope: const VaultImportScope(),
            state: ImportJobState.committing,
            attemptCount: 1,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            payload: ImportJobSensitivePayload(
              sourceAssetId: a2.id,
              displayName: a2.name,
              mimeType: 'image/jpeg',
              expectedSizeBytes: p2Bytes.length,
              contentHash: PhotoMeta.computeHash(p2Bytes),
            ),
          ),
          DurableImportJob(
            jobId: 'j3',
            batchId: 'b1',
            destId: dest3,
            enqueueOrder: 3,
            mediaKind: ImportMediaKind.photo,
            scope: const VaultImportScope(),
            state: ImportJobState.encrypting,
            attemptCount: 1,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            payload: ImportJobSensitivePayload(
              sourceAssetId: a3.id,
              displayName: a3.name,
              mimeType: 'image/jpeg',
              expectedSizeBytes: p3Bytes.length,
            ),
          ),
          DurableImportJob(
            jobId: 'j4',
            batchId: 'b1',
            destId: dest4,
            enqueueOrder: 4,
            mediaKind: ImportMediaKind.video,
            scope: const VaultImportScope(),
            state: ImportJobState.encrypting,
            attemptCount: 1,
            stagingName: '$dest4.part',
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            payload: ImportJobSensitivePayload(
              sourceAssetId: a4.id,
              displayName: a4.name,
              mimeType: 'video/mp4',
              durationSeconds: 7,
              expectedSizeBytes: p4Bytes.length,
            ),
          ),
        ]);

        // Verify privacy in raw SQLite bytes BEFORE tearing down process 1:
        // sensitive filenames, paths, and asset IDs must NEVER appear plaintext!
        final rawDbBytes = File(
          p.join(dbDir.path, kImportJournalDbFileName),
        ).readAsBytesSync();
        final rawLatin = latin1.decode(rawDbBytes, allowInvalid: true);
        expect(rawLatin.contains('already_done_secret.jpg'), isFalse);
        expect(rawLatin.contains('rec_done_id_secret'), isFalse);
        expect(rawLatin.contains(sourceDir.path), isFalse);

        await journal1.close();
        await fv1.closeDatabase();
        await vv1.closeDatabase();
        crypto1.lock();

        // Process 2: brand new VaultCrypto instance unlocked with PIN '1234'
        final crypto2 = VaultCrypto(platform, keystore);
        expect(await crypto2.verifyPin('1234'), isTrue);
        await crypto2.initialize('1234');
        final fv2 = FileVaultService(platform, crypto2);
        final vv2 = VideoVaultService(platform, crypto2);
        final journal2 = ImportJournalStore(crypto2);
        final coordinator2 = ImportCoordinator(
          crypto: crypto2,
          platformService: platform,
          fileVault: fv2,
          videoVault: vv2,
          pickerAdapter: picker,
          journal: journal2,
          storageProbe: () async => 500 * 1024 * 1024,
        );

        try {
          await coordinator2.syncAfterUnlock();
          await waitUntilSettled(coordinator2);

          final photos = await fv2.getAllPhotos();
          final videos = await vv2.getAllVideos();
          expect(photos.map((e) => e.id).toSet(), {dest1, dest2, dest3});
          expect(videos.map((e) => e.id).toSet(), {dest4});

          expect(await fv2.getPhoto(dest1), p1Bytes);
          expect(await fv2.getPhoto(dest2), p2Bytes);
          expect(await fv2.getPhoto(dest3), p3Bytes);
          expect(await vv2.getVideo(dest4), p4Bytes);
          expect(stage4.existsSync(), isFalse);
        } finally {
          await disposeEnv(
            coordinator: coordinator2,
            fileVault: fv2,
            videoVault: vv2,
            journal: journal2,
          );
        }
      },
    );
  });

  group('4 · Source, Permission, Storage, DB Failures & Deletion Matrix', () {
    test(
      'handles per-file missing, cloud-only, and corrupt sources alongside healthy files',
      () async {
        final env = await buildEnv();
        try {
          final missing = _ControlledGalleryAsset(
            id: 'm1',
            kind: ImportMediaKind.photo,
            name: 'missing.jpg',
            mimeType: 'image/jpeg',
            file: File(p.join(sourceDir.path, 'nonexistent.jpg')),
          );
          final cloud = _ControlledGalleryAsset(
            id: 'c1',
            kind: ImportMediaKind.video,
            name: 'icloud.mp4',
            mimeType: 'video/mp4',
            durationS: 4,
            file: writeGalleryFile('icloud.mp4', deterministicPayload(51, 512)),
            forcedFailureStatus: MediaSourceResolutionStatus.cloudUnavailable,
          );
          final corruptRead = _ControlledGalleryAsset(
            id: 'bad1',
            kind: ImportMediaKind.photo,
            name: 'corrupt.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile(
              'corrupt.jpg',
              deterministicPayload(52, 512),
            ),
          )..throwUnreadableHash = true;
          final healthy = _ControlledGalleryAsset(
            id: 'ok1',
            kind: ImportMediaKind.photo,
            name: 'healthy.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile(
              'healthy.jpg',
              deterministicPayload(53, 2048),
            ),
          );
          env.picker
            ..addAsset(missing)
            ..addAsset(cloud)
            ..addAsset(corruptRead)
            ..addAsset(healthy);

          await env.coordinator.enqueueBatch(
            sources: [
              missing.toRef(),
              cloud.toRef(),
              corruptRead.toRef(),
              healthy.toRef(),
            ],
            scope: const VaultImportScope(),
          );
          await waitUntilSettled(env.coordinator);

          expect(env.coordinator.jobs[0].state, ImportJobState.needsSource);
          expect(env.coordinator.jobs[1].state, ImportJobState.needsSource);
          expect(env.coordinator.jobs[2].state, ImportJobState.failed);
          expect(
            env.coordinator.jobs[3].state,
            ImportJobState.savedOriginalKept,
          );
          expect((await env.fileVault.getAllPhotos()).length, 1);
          expect(
            env.picker.deleteRequests,
            isEmpty,
            reason: 'Partial-failure batch must NEVER trigger OS delete',
          );
        } finally {
          await disposeEnv(
            coordinator: env.coordinator,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            journal: env.journal,
          );
        }
      },
    );

    test(
      'permission revocation & low storage pause queue dispatch cleanly and Retry completes all items',
      () async {
        final env = await buildEnv();
        try {
          final f1 = _ControlledGalleryAsset(
            id: 'f1',
            kind: ImportMediaKind.photo,
            name: 'f1.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('f1.jpg', deterministicPayload(61, 4096)),
          );
          final f2 = _ControlledGalleryAsset(
            id: 'f2',
            kind: ImportMediaKind.photo,
            name: 'f2.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('f2.jpg', deterministicPayload(62, 4096)),
          );
          env.picker
            ..addAsset(f1)
            ..addAsset(f2);
          env.picker.permissionState = PermissionState.denied;

          await env.coordinator.enqueueBatch(
            sources: [f1.toRef(), f2.toRef()],
            scope: const VaultImportScope(),
          );
          await waitUntilSettled(env.coordinator);

          expect(env.coordinator.isPaused, isTrue);
          expect(
            env.coordinator.pauseReason,
            ImportPauseReason.permissionDenied,
          );
          expect(env.coordinator.jobs[0].state, ImportJobState.needsSource);
          expect(env.coordinator.jobs[1].state, ImportJobState.queued);

          // Restore permission, trigger full-storage condition
          env.picker.permissionState = PermissionState.authorized;
          env.setAvailableBytes(1024); // < 8 MB reserve -> lowStorage pause!
          await env.coordinator.retryEligible();
          await waitUntilSettled(env.coordinator);

          expect(env.coordinator.isPaused, isTrue);
          expect(env.coordinator.pauseReason, ImportPauseReason.lowStorage);
          expect(
            env.coordinator.jobs.every((j) => j.state == ImportJobState.queued),
            isTrue,
          );

          // Free space -> Retry completes all items
          env.setAvailableBytes(500 * 1024 * 1024);
          await env.coordinator.retryEligible();
          await waitUntilSettled(env.coordinator);

          expect((await env.fileVault.getAllPhotos()).length, 2);
        } finally {
          await disposeEnv(
            coordinator: env.coordinator,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            journal: env.journal,
          );
        }
      },
    );

    test(
      'database failure pauses safely without silently losing queued work',
      () async {
        final platform = AndroidPlatformService();
        final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
        final fileVault = FileVaultService(platform, crypto);
        final videoVault = VideoVaultService(platform, crypto);
        final picker = _ControllablePickerAdapter();
        final faultyJournal = _FaultyJournalStore(crypto);
        final coordinator = ImportCoordinator(
          crypto: crypto,
          platformService: platform,
          fileVault: fileVault,
          videoVault: videoVault,
          pickerAdapter: picker,
          journal: faultyJournal,
          storageProbe: () async => 500 * 1024 * 1024,
        );

        try {
          final f1 = _ControlledGalleryAsset(
            id: 'db1',
            kind: ImportMediaKind.photo,
            name: 'db1.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('db1.jpg', deterministicPayload(88, 1024)),
          );
          picker.addAsset(f1);

          faultyJournal.failNextLoad = true;
          await coordinator.syncAfterUnlock();
          expect(coordinator.pauseReason, ImportPauseReason.databaseFailure);

          faultyJournal.failNextLoad = false;
          faultyJournal.failNextInsert = true;
          await expectLater(
            coordinator.enqueueBatch(
              sources: [f1.toRef()],
              scope: const VaultImportScope(),
            ),
            throwsA(isA<ImportJournalException>()),
          );
          expect(coordinator.pauseReason, ImportPauseReason.databaseFailure);
        } finally {
          await disposeEnv(
            coordinator: coordinator,
            fileVault: fileVault,
            videoVault: videoVault,
            journal: faultyJournal,
          );
        }
      },
    );

    test(
      'deferred original deletion tracks denied and partial OS delete confirmations accurately',
      () async {
        final env = await buildEnv();
        try {
          final d1 = _ControlledGalleryAsset(
            id: 'd1',
            kind: ImportMediaKind.photo,
            name: 'd1.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('d1.jpg', deterministicPayload(91, 1024)),
            deleteConfirmed: true,
          );
          final d2 = _ControlledGalleryAsset(
            id: 'd2',
            kind: ImportMediaKind.photo,
            name: 'd2.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('d2.jpg', deterministicPayload(92, 1024)),
            deleteConfirmed: false, // Refused / skipped by OS!
          );
          final d3 = _ControlledGalleryAsset(
            id: 'd3',
            kind: ImportMediaKind.photo,
            name: 'd3.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile('d3.jpg', deterministicPayload(93, 1024)),
            deleteConfirmed: true,
          );
          env.picker
            ..addAsset(d1)
            ..addAsset(d2)
            ..addAsset(d3);

          // No foreground UI token acquired yet -> delete confirmation deferred!
          await env.coordinator.enqueueBatch(
            sources: [d1.toRef(), d2.toRef(), d3.toRef()],
            scope: const VaultImportScope(),
          );
          await waitUntilSettled(env.coordinator);
          expect(env.picker.deleteRequests, isEmpty);
          expect(
            env.coordinator.jobs.every(
              (j) => j.state == ImportJobState.awaitingDeleteConfirmation,
            ),
            isTrue,
          );

          // First simulate full permission refusal
          env.picker.throwDeletePermissionDenied = true;
          final fgToken = env.coordinator.acquireForegroundUi();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(env.picker.deleteRequests.length, 1);
          expect(
            env.coordinator.jobs.every(
              (j) => j.state == ImportJobState.savedOriginalKept,
            ),
            isTrue,
          );
          expect(d1.file.existsSync(), isTrue);
          expect(d2.file.existsSync(), isTrue);
          expect(d3.file.existsSync(), isTrue);
          env.coordinator.releaseForegroundUi(fgToken);

          // Next batch: partial OS deletion ([d1, d3] deleted, d2 kept)
          env.picker.throwDeletePermissionDenied = false;
          await env.coordinator.clearFinished();
          final b2 = await env.coordinator.enqueueBatch(
            sources: [d1.toRef(), d2.toRef(), d3.toRef()],
            scope: const VaultImportScope(),
          );
          expect(b2, isNotNull);
          await waitUntilSettled(env.coordinator);

          final fgToken2 = env.coordinator.acquireForegroundUi();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          env.coordinator.releaseForegroundUi(fgToken2);

          expect(env.coordinator.jobs[0].state, ImportJobState.saved);
          expect(
            env.coordinator.jobs[1].state,
            ImportJobState.savedOriginalKept,
          );
          expect(env.coordinator.jobs[2].state, ImportJobState.saved);
          expect(d1.file.existsSync(), isFalse);
          expect(d2.file.existsSync(), isTrue);
          expect(d3.file.existsSync(), isFalse);
        } finally {
          await disposeEnv(
            coordinator: env.coordinator,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            journal: env.journal,
          );
        }
      },
    );
  });

  group('5 · Key Isolation & Wipe Non-Resurrection', () {
    test(
      'different master key / wipe cannot decrypt or resurrect jobs',
      () async {
        final env = await buildEnv();
        try {
          final s1 = _ControlledGalleryAsset(
            id: 'iso1',
            kind: ImportMediaKind.photo,
            name: 'secret_real.jpg',
            mimeType: 'image/jpeg',
            file: writeGalleryFile(
              'secret_real.jpg',
              deterministicPayload(99, 1024),
            ),
          );
          env.picker.addAsset(s1);

          final barrierHit = Completer<void>();
          final release = Completer<void>();
          final hooked = ImportCoordinator(
            crypto: env.crypto,
            platformService: env.platform,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            pickerAdapter: env.picker,
            journal: env.journal,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                if (!barrierHit.isCompleted) barrierHit.complete();
                await release.future;
              },
            ),
          );
          env.coordinator.dispose();

          await hooked.enqueueBatch(
            sources: [s1.toRef()],
            scope: const VaultImportScope(),
          );
          await barrierHit.future;

          expect(hooked.jobsForScope(const VaultImportScope()).length, 1);

          // Lock (as during Decoy/Duress): jobs hidden & unresumable without real DEK
          env.crypto.lock();
          expect(hooked.jobs, isEmpty);
          expect(hooked.uiSession.isActive, isFalse);

          // Wrong master key cannot decrypt saved job payloads
          env.crypto.unlockWithKey(masterKeyB);
          await hooked.syncAfterUnlock();
          expect(hooked.jobs, isEmpty);

          // Restore real key then run VaultWipeService -> nothing resurrects
          env.crypto.lock();
          env.crypto.unlockWithKey(masterKeyA);
          await hooked.syncAfterUnlock();
          release.complete();
          await waitUntilSettled(hooked);

          final wipeService = VaultWipeService(
            env.platform,
            env.fileVault,
            env.videoVault,
            NotesService(env.platform, env.crypto),
            DocumentVaultService(env.platform, env.crypto),
          );
          await wipeService.wipeAllContent();

          // Also run PinWipeService cleanly
          final pinWipe = PinWipeService(
            env.platform,
            keystoreService: _PassThroughKeystore(),
          );
          await pinWipe.wipePin();

          await hooked.syncAfterUnlock();
          expect(hooked.jobs, isEmpty);
          expect(
            File(p.join(dbDir.path, kImportJournalDbFileName)).existsSync(),
            isFalse,
          );
          hooked.dispose();
        } finally {
          await env.fileVault.closeDatabase();
          await env.videoVault.closeDatabase();
          await env.journal.close();
        }
      },
    );
  });

  group(
    '6 · Background FGS Bridge, Bounded Stall/Ceiling, Immediate Lock & Process Death',
    () {
      test(
        'FGS starts, updates generic count-only progress, stops, and destroys DEK immediately on finish when UI is unauthorized',
        () async {
          final platform = AndroidPlatformService();
          final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final videoVault = VideoVaultService(platform, crypto);
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);
          final bridge = _FakeBackgroundImportBridge();
          final gate = Completer<void>();
          final item3Entered = Completer<void>();
          var itemCounter = 0;

          late final VaultUiAccessController uiAccess;
          late final ImportCoordinator coordinator;
          final container = ProviderContainer(
            overrides: [
              vaultCryptoProvider.overrideWith((_) => crypto),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
            ],
          );
          uiAccess = container.read(vaultUiAccessProvider);
          AutoLock().attachContainerForTesting(container);

          coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            backgroundBridge: bridge,
            uiAccess: uiAccess,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                itemCounter++;
                if (itemCounter == 3) {
                  if (!item3Entered.isCompleted) item3Entered.complete();
                  await gate.future;
                }
              },
            ),
          );

          try {
            final refs = <MediaSourceRef>[];
            for (var i = 0; i < 3; i++) {
              final name = 'bg_secret_$i.jpg';
              final a = _ControlledGalleryAsset(
                id: 'bg_$i',
                kind: ImportMediaKind.photo,
                name: name,
                mimeType: 'image/jpeg',
                file: writeGalleryFile(
                  name,
                  deterministicPayload(400 + i, 2048),
                ),
              );
              picker.addAsset(a);
              refs.add(a.toRef());
            }

            await coordinator.enqueueBatch(
              sources: refs,
              scope: const VaultImportScope(),
            );
            await item3Entered.future;

            expect(bridge.startCalls.length, 1);
            expect(bridge.startCalls.first.total, 3);
            expect(bridge.updateCalls.isNotEmpty, isTrue);
            expect(bridge.stopCount, 0);

            // User left vault & UI access expired while item 3 is encrypting
            uiAccess.requireReauthentication(reason: 'background_ui_timeout');
            expect(uiAccess.isUiAuthorized, isFalse);
            expect(
              crypto.isUnlocked,
              isTrue,
              reason: 'Worker still actively progressing',
            );

            // Release item 3: worker finishes 3/3, stops FGS, AND immediately wipes DEK!
            gate.complete();
            await waitUntil(() => !crypto.isUnlocked, crypto);

            expect(crypto.isUnlocked, isFalse);
            expect(AutoLock().hasActiveImportAuthorization, isFalse);
            expect(bridge.stopCount, greaterThanOrEqualTo(1));

            // Genuine unlock confirms all 3 items saved without duplicates
            crypto.unlockWithKey(masterKeyA);
            await coordinator.syncAfterUnlock();
            await waitUntilSettled(coordinator);
            expect((await fileVault.getAllPhotos()).length, 3);
          } finally {
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            coordinator.dispose();
            container.dispose();
            await journal.close();
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
          }
        },
      );

      test(
        'notification Pause & Cancel commands and Android onTimeout/OS stop behave safely without losing saved work',
        () async {
          final platform = AndroidPlatformService();
          final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final videoVault = VideoVaultService(platform, crypto);
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);
          final bridge = _FakeBackgroundImportBridge();
          var enteredCount = 0;
          Completer<void>? itemGate;
          Completer<void>? reachedSecond;

          final container = ProviderContainer(
            overrides: [
              vaultCryptoProvider.overrideWith((_) => crypto),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
            ],
          );
          final uiAccess = container.read(vaultUiAccessProvider);
          AutoLock().attachContainerForTesting(container);

          final coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            backgroundBridge: bridge,
            uiAccess: uiAccess,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                enteredCount++;
                if (enteredCount == 2) {
                  if (reachedSecond != null && !reachedSecond.isCompleted) {
                    reachedSecond.complete();
                  }
                  if (itemGate != null) await itemGate.future;
                }
              },
            ),
          );

          try {
            final refs = <MediaSourceRef>[];
            for (var i = 0; i < 4; i++) {
              final name = 'cmd_$i.jpg';
              final a = _ControlledGalleryAsset(
                id: 'cmd_$i',
                kind: ImportMediaKind.photo,
                name: name,
                mimeType: 'image/jpeg',
                file: writeGalleryFile(
                  name,
                  deterministicPayload(500 + i, 2048),
                ),
              );
              picker.addAsset(a);
              refs.add(a.toRef());
            }

            reachedSecond = Completer<void>();
            itemGate = Completer<void>();
            await coordinator.enqueueBatch(
              sources: refs,
              scope: const VaultImportScope(),
            );
            await reachedSecond.future;

            // 1) Notification Pause while UI unauthorized -> pauses cleanly, stops FGS, wipes DEK!
            uiAccess.requireReauthentication(reason: 'ui_timeout');
            bridge.emitCommand(BackgroundImportCommand.pauseRequested);
            await waitUntil(() => !crypto.isUnlocked, crypto);
            itemGate.complete();
            expect(bridge.stopCount, greaterThanOrEqualTo(1));
            expect(crypto.isUnlocked, isFalse);

            // Genuine unlock recovers & finishes all 4
            itemGate = null;
            crypto.unlockWithKey(masterKeyA);
            await coordinator.syncAfterUnlock();
            await waitUntilSettled(coordinator);
            expect((await fileVault.getAllPhotos()).length, 4);

            // 2) Android onTimeout & OS stop cleanly pause without dropping work
            enteredCount = 0;
            reachedSecond = Completer<void>();
            itemGate = Completer<void>();
            final refs2 = <MediaSourceRef>[];
            for (var i = 4; i < 6; i++) {
              final name = 'cmd_$i.jpg';
              final a = _ControlledGalleryAsset(
                id: 'cmd_$i',
                kind: ImportMediaKind.photo,
                name: name,
                mimeType: 'image/jpeg',
                file: writeGalleryFile(
                  name,
                  deterministicPayload(500 + i, 2048),
                ),
              );
              picker.addAsset(a);
              refs2.add(a.toRef());
            }
            await coordinator.enqueueBatch(
              sources: refs2,
              scope: const VaultImportScope(),
            );
            await waitUntil(
              () => enteredCount >= 1 && coordinator.isWorking,
              coordinator,
            );
            bridge.emitCommand(BackgroundImportCommand.serviceTimedOut);
            itemGate.complete();
            await waitUntil(
              () => !coordinator.isWorking && bridge.stopCount >= 2,
              coordinator,
            );

            expect(coordinator.isPaused, isTrue);
            expect(coordinator.pauseReason, ImportPauseReason.serviceTimedOut);
            expect(bridge.stopCount, greaterThanOrEqualTo(2));

            itemGate = null;
            await coordinator.retryEligible();
            await waitUntilSettled(coordinator);
            expect((await fileVault.getAllPhotos()).length, 6);
          } finally {
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            coordinator.dispose();
            container.dispose();
            await journal.close();
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
          }
        },
      );

      test(
        'notification/service start denial surfaces honest warning without dropping queue',
        () async {
          final env = await buildEnv();
          final bridge = _FakeBackgroundImportBridge(
            startResult: const BackgroundServiceStartResult(
              started: false,
              notificationsGranted: false,
              errorCode: 'start_not_allowed',
              safeMessage: 'Android restricted background service start.',
            ),
          );
          final coordinator = ImportCoordinator(
            crypto: env.crypto,
            platformService: env.platform,
            fileVault: env.fileVault,
            videoVault: env.videoVault,
            pickerAdapter: env.picker,
            journal: env.journal,
            backgroundBridge: bridge,
            storageProbe: () async => 500 * 1024 * 1024,
          );
          env.coordinator.dispose();

          try {
            final a = _ControlledGalleryAsset(
              id: 'deny1',
              kind: ImportMediaKind.photo,
              name: 'deny1.jpg',
              mimeType: 'image/jpeg',
              file: writeGalleryFile(
                'deny1.jpg',
                deterministicPayload(701, 1024),
              ),
            );
            env.picker.addAsset(a);
            await coordinator.enqueueBatch(
              sources: [a.toRef()],
              scope: const VaultImportScope(),
            );
            await waitUntilSettled(coordinator);

            expect(
              coordinator.backgroundServiceWarning,
              contains('Android restricted'),
            );
            expect((await env.fileVault.getAllPhotos()).length, 1);
            expect(bridge.stopCount, greaterThanOrEqualTo(1));
          } finally {
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            await disposeEnv(
              coordinator: coordinator,
              fileVault: env.fileVault,
              videoVault: env.videoVault,
              journal: env.journal,
            );
          }
        },
      );

      test(
        'bounded stall watchdog & non-resetting 30-minute ceiling prevent indefinite exemption and survive process death cleanly',
        () async {
          final platform = AndroidPlatformService();
          final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final videoVault = VideoVaultService(platform, crypto);
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);
          final bridge = _FakeBackgroundImportBridge();
          final container = ProviderContainer(
            overrides: [
              vaultCryptoProvider.overrideWith((_) => crypto),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
            ],
          );
          final uiAccess = container.read(vaultUiAccessProvider);
          AutoLock().attachContainerForTesting(container);

          var now = DateTime(2026, 5, 1, 10, 0, 0);
          AutoLock().setNowForTesting(() => now);
          AutoLock().setImportStallDeadlineForTesting(
            const Duration(seconds: 10),
          );

          final entered = Completer<void>();
          final gate = Completer<void>();

          final coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            backgroundBridge: bridge,
            uiAccess: uiAccess,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                if (!entered.isCompleted) entered.complete();
                await gate.future;
              },
            ),
          );

          try {
            final a1 = _ControlledGalleryAsset(
              id: 'wd1',
              kind: ImportMediaKind.photo,
              name: 'wd1.jpg',
              mimeType: 'image/jpeg',
              file: writeGalleryFile(
                'wd1.jpg',
                deterministicPayload(801, 2048),
              ),
            );
            final a2 = _ControlledGalleryAsset(
              id: 'wd2',
              kind: ImportMediaKind.photo,
              name: 'wd2.jpg',
              mimeType: 'image/jpeg',
              file: writeGalleryFile(
                'wd2.jpg',
                deterministicPayload(802, 2048),
              ),
            );
            picker
              ..addAsset(a1)
              ..addAsset(a2);

            await coordinator.enqueueBatch(
              sources: [a1.toRef()],
              scope: const VaultImportScope(),
            );
            await entered.future;

            final initialCeiling = AutoLock().importCeilingDeadlineForTesting!;
            expect(initialCeiling, now.add(const Duration(minutes: 30)));

            // Genuine progress ticks keep lease alive & UI expired separately
            uiAccess.requireReauthentication(reason: 'ui_idle_timeout');
            now = now.add(const Duration(seconds: 6));
            AutoLock().recordImportProgress();
            AutoLock().checkImportWatchdogsNow();
            expect(AutoLock().hasActiveImportAuthorization, isTrue);
            expect(crypto.isUnlocked, isTrue);

            // Appending another batch at T+20m NEVER extends the 30-minute ceiling!
            now = now.add(const Duration(minutes: 14));
            AutoLock().recordImportProgress();
            await coordinator.enqueueBatch(
              sources: [a2.toRef()],
              scope: const VaultImportScope(),
            );
            expect(
              AutoLock().importCeilingDeadlineForTesting,
              initialCeiling,
              reason:
                  'Appending a batch must never reset the 30m exemption window',
            );

            // Stall (> 10s without progress) while UI is unauthorized -> immediate lock + FGS stop!
            now = now.add(const Duration(seconds: 15));
            AutoLock().checkImportWatchdogsNow();
            await waitUntil(() => !crypto.isUnlocked, crypto);

            expect(AutoLock().hasActiveImportAuthorization, isFalse);
            expect(crypto.isUnlocked, isFalse);
            expect(bridge.stopCount, greaterThanOrEqualTo(1));

            // Process termination / cold start: locked VaultCrypto must NEVER auto-resume!
            gate.complete();
            coordinator.dispose();
            await journal.close();
            final freshLockedCrypto = _HarnessCrypto(); // locked!
            final coldCoordinator = ImportCoordinator(
              crypto: freshLockedCrypto,
              platformService: platform,
              fileVault: FileVaultService(platform, freshLockedCrypto),
              videoVault: VideoVaultService(platform, freshLockedCrypto),
              pickerAdapter: picker,
              journal: ImportJournalStore(freshLockedCrypto),
              backgroundBridge: _FakeBackgroundImportBridge(),
            );
            await coldCoordinator.syncAfterUnlock();
            expect(coldCoordinator.isWorking, isFalse);
            expect(coldCoordinator.jobs, isEmpty);
            coldCoordinator.dispose();
          } finally {
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            container.dispose();
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
          }
        },
      );

      test(
        'stale native service events arriving after lock or completion never cancel paused or saved jobs',
        () async {
          final platform = AndroidPlatformService();
          final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final videoVault = VideoVaultService(platform, crypto);
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);
          final bridge = _FakeBackgroundImportBridge();

          final enteredFirst = Completer<void>();
          final firstGate = Completer<void>();
          var gatedOnce = true;

          final coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            backgroundBridge: bridge,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                if (gatedOnce) {
                  if (!enteredFirst.isCompleted) enteredFirst.complete();
                  await firstGate.future;
                }
              },
            ),
          );

          try {
            final refs = <MediaSourceRef>[];
            for (var i = 0; i < 3; i++) {
              final name = 'late_evt_$i.jpg';
              final asset = _ControlledGalleryAsset(
                id: 'late_evt_$i',
                kind: ImportMediaKind.photo,
                name: name,
                mimeType: 'image/jpeg',
                file: writeGalleryFile(
                  name,
                  deterministicPayload(910 + i, 2048),
                ),
              );
              picker.addAsset(asset);
              refs.add(asset.toRef());
            }

            await coordinator.enqueueBatch(
              sources: refs,
              scope: const VaultImportScope(),
            );
            await enteredFirst.future;

            // Manual lock freezes work; delayed native pause/cancel/stop events must NOT cancel jobs.
            crypto.lock();
            firstGate.complete();
            await waitUntil(() => !coordinator.isWorking, coordinator);

            bridge.emitCommand(BackgroundImportCommand.cancelRequested);
            bridge.emitCommand(BackgroundImportCommand.pauseRequested);
            bridge.emitCommand(BackgroundImportCommand.serviceStoppedByOs);
            bridge.emitCommand(BackgroundImportCommand.serviceTimedOut);
            await Future<void>.delayed(const Duration(milliseconds: 20));

            expect(coordinator.pauseReason, ImportPauseReason.locked);

            // Unlock recovers all 3 queued items intact.
            gatedOnce = false;
            crypto.unlockWithKey(masterKeyA);
            await coordinator.syncAfterUnlock();
            await waitUntilSettled(coordinator);
            expect((await fileVault.getAllPhotos()).length, 3);
            expect(coordinator.jobs.every((j) => j.isCommittedToVault), isTrue);

            // Late OS service stop after completion must not flip completed session to paused.
            bridge.emitCommand(BackgroundImportCommand.serviceStoppedByOs);
            bridge.emitCommand(BackgroundImportCommand.serviceTimedOut);
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(coordinator.pauseReason, ImportPauseReason.none);
            expect(coordinator.isPaused, isFalse);
          } finally {
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            coordinator.dispose();
            await journal.close();
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
          }
        },
      );

      test(
        'streaming SHA-256 hashing emits cumulative multi-chunk byte progress',
        () async {
          final bytes = deterministicPayload(990, 600 * 1024 + 123);
          final file = writeGalleryFile('hash_progress_test.mp4', bytes);
          final ticks = <int>[];

          final digest =
              await VaultMediaCommitHelper.computeFileSha256Streaming(
                file,
                onBytesProgress: ticks.add,
              );

          expect(digest, sha256.convert(bytes).toString());
          expect(ticks.length, greaterThanOrEqualTo(3));
          for (var i = 1; i < ticks.length; i++) {
            expect(ticks[i], greaterThan(ticks[i - 1]));
          }
          expect(ticks.last, bytes.length);
        },
      );

      test(
        'coordinator projects live Preparing and Encrypting percent, keeps stall lease alive during slow hash, updates notification percent, and clears progress cleanly',
        () async {
          final platform = AndroidPlatformService();
          final crypto = _HarnessCrypto()..unlockWithKey(masterKeyA);
          final fileVault = FileVaultService(platform, crypto);
          final firstHashChunkSeen = Completer<void>();
          final resumeHash = Completer<void>();
          final videoVault = _ProgressGatingVideoVaultService(
            platform,
            crypto,
            onHashChunk: (bytes) async {
              if (!firstHashChunkSeen.isCompleted) {
                firstHashChunkSeen.complete();
                await resumeHash.future;
              }
            },
          );
          final picker = _ControllablePickerAdapter();
          final journal = ImportJournalStore(crypto);
          final bridge = _FakeBackgroundImportBridge();
          final container = ProviderContainer(
            overrides: [
              vaultCryptoProvider.overrideWith((_) => crypto),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
            ],
          );
          final uiAccess = container.read(vaultUiAccessProvider);
          AutoLock().attachContainerForTesting(container);

          var now = DateTime(2026, 5, 2, 12, 0, 0);
          AutoLock().setNowForTesting(() => now);
          AutoLock().setImportStallDeadlineForTesting(
            const Duration(seconds: 10),
          );

          final beforeEncryptGate = Completer<void>();
          final resumeEncrypt = Completer<void>();
          final coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            backgroundBridge: bridge,
            uiAccess: uiAccess,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                if (!beforeEncryptGate.isCompleted) {
                  beforeEncryptGate.complete();
                }
                await resumeEncrypt.future;
              },
            ),
          );

          final observedPreparingProgress = <double>[];
          final observedPreparingDetails = <String>[];
          final observedEncryptingProgress = <double>[];
          final observedEncryptingDetails = <String>[];
          ImportFileEntry? observedSavedEntry;
          void sessionListener() {
            for (final entry in coordinator.uiSession.files) {
              if (entry.status == ImportFileStatus.preparing &&
                  entry.progress != null) {
                observedPreparingProgress.add(entry.progress!);
                if (entry.detail != null) {
                  observedPreparingDetails.add(entry.detail!);
                }
              } else if (entry.status == ImportFileStatus.encrypting &&
                  entry.progress != null) {
                observedEncryptingProgress.add(entry.progress!);
                if (entry.detail != null) {
                  observedEncryptingDetails.add(entry.detail!);
                }
              } else if (entry.status == ImportFileStatus.savedOriginalKept) {
                observedSavedEntry = entry;
              }
            }
          }

          coordinator.uiSession.addListener(sessionListener);

          try {
            // > 768 KB payload guarantees multiple 256 KB SHA-256 chunks and multiple 64 KB CTR chunks.
            final payload = deterministicPayload(991, 800 * 1024);
            final asset = _ControlledGalleryAsset(
              id: 'live_prog_vid',
              kind: ImportMediaKind.video,
              name: 'large_clip.mp4',
              mimeType: 'video/mp4',
              durationS: 14,
              file: writeGalleryFile('large_clip.mp4', payload),
            );
            picker.addAsset(asset);

            await coordinator.enqueueBatch(
              sources: [asset.toRef()],
              scope: const VaultImportScope(),
            );

            await firstHashChunkSeen.future;
            // UI timeout expires while background import lease is active.
            uiAccess.requireReauthentication(reason: 'ui_idle_timeout');

            // First 6s step passes while stalled only briefly (< 10s), and UI already sees Preparing %.
            now = now.add(const Duration(seconds: 6));
            expect(observedPreparingProgress, isNotEmpty);
            expect(observedPreparingProgress.first, greaterThan(0.0));
            expect(observedPreparingProgress.first, lessThan(1.0));
            expect(
              observedPreparingDetails.any((d) => d.startsWith('Checking · ')),
              isTrue,
            );

            // Allow remaining hash chunks to proceed -> each chunk calls lease.recordProgress().
            resumeHash.complete();
            await beforeEncryptGate.future;

            // T+12s (> 10s initial deadline) BEFORE encryption even starts must still be active
            // because Preparing hash chunks refreshed AutoLock's stall lease.
            now = now.add(const Duration(seconds: 6));
            AutoLock().checkImportWatchdogsNow();
            expect(AutoLock().hasActiveImportAuthorization, isTrue);
            expect(crypto.isUnlocked, isTrue);

            resumeEncrypt.complete();
            await waitUntilSettled(coordinator);
            // Because UI timeout expired while importing in the background,
            // finishing the batch releases the lease and locks the vault key.
            await waitUntil(() => !crypto.isUnlocked, coordinator);

            expect(observedEncryptingProgress, isNotEmpty);
            expect(
              observedEncryptingProgress.any((p) => p > 0.0 && p < 1.0),
              isTrue,
            );
            expect(
              observedEncryptingDetails.any(
                (d) => d.startsWith('Encrypting · '),
              ),
              isTrue,
            );
            expect(observedSavedEntry, isNotNull);
            expect(observedSavedEntry!.progress, isNull);
            expect(observedSavedEntry!.detail, isNull);
            expect(coordinator.jobs, isEmpty);
            expect(
              bridge.updateCalls.any(
                (c) =>
                    c.activePercent != null &&
                    c.activePercent! > 0 &&
                    c.activePercent! < 100,
              ),
              isTrue,
            );
            crypto.unlockWithKey(masterKeyA);
            await coordinator.syncAfterUnlock();
            expect(coordinator.jobs.single.isCommittedToVault, isTrue);
            expect(
              coordinator.jobs.single.state,
              anyOf(
                ImportJobState.savedOriginalKept,
                ImportJobState.awaitingDeleteConfirmation,
              ),
            );
            expect((await videoVault.getAllVideos()).length, 1);
          } finally {
            coordinator.uiSession.removeListener(sessionListener);
            if (!resumeHash.isCompleted) resumeHash.complete();
            if (!resumeEncrypt.isCompleted) resumeEncrypt.complete();
            coordinator.dispose();
            await Future<void>.delayed(const Duration(milliseconds: 20));
            AutoLock().dispose();
            AutoLock().resetClockForTesting();
            container.dispose();
            await journal.close();
            await fileVault.closeDatabase();
            await videoVault.closeDatabase();
          }
        },
      );
    },
  );
}

class _FakeBackgroundImportBridge implements BackgroundImportBridge {
  final List<({int completed, int total, int? activePercent})> startCalls = [];
  final List<({int completed, int total, int? activePercent})> updateCalls = [];
  int stopCount = 0;
  BackgroundServiceStartResult startResult;
  void Function(BackgroundImportCommand command)? _handler;

  _FakeBackgroundImportBridge({
    this.startResult = const BackgroundServiceStartResult(
      started: true,
      notificationsGranted: true,
    ),
  });

  void emitCommand(BackgroundImportCommand cmd) => _handler?.call(cmd);

  @override
  Future<bool> hasNotificationPermission() async =>
      startResult.notificationsGranted;

  @override
  Future<bool> requestNotificationPermission() async =>
      startResult.notificationsGranted;

  @override
  Future<BackgroundServiceStartResult> startImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    startCalls.add((
      completed: completed,
      total: total,
      activePercent: activePercent,
    ));
    return startResult;
  }

  @override
  Future<void> updateImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    updateCalls.add((
      completed: completed,
      total: total,
      activePercent: activePercent,
    ));
  }

  @override
  Future<void> stopImportService() async {
    stopCount++;
  }

  @override
  void setCommandHandler(
    void Function(BackgroundImportCommand command)? handler,
  ) {
    _handler = handler;
  }

  @override
  void dispose() {
    _handler = null;
  }
}

class _ProgressGatingVideoVaultService extends VideoVaultService {
  final Future<void> Function(int bytesProcessed) onHashChunk;

  _ProgressGatingVideoVaultService(
    super.platformService,
    super.crypto, {
    required this.onHashChunk,
  });

  @override
  Future<String> computeFileSha256(
    File source, {
    bool Function()? shouldAbort,
    void Function(int bytesProcessed)? onBytesProgress,
  }) async {
    final raf = await source.open(mode: FileMode.read);
    final bytes = await raf.read(await source.length());
    await raf.close();
    const chunkSize = 256 * 1024;
    var offset = 0;
    while (offset < bytes.length) {
      if (shouldAbort != null && shouldAbort()) {
        throw const OperationCancelledException();
      }
      final nextEnd = (offset + chunkSize).clamp(0, bytes.length);
      offset = nextEnd;
      onBytesProgress?.call(offset);
      await onHashChunk(offset);
    }
    return sha256.convert(bytes).toString();
  }
}
