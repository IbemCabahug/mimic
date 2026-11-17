import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mimic/core/router/app_router.dart' as router;
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/crypto_isolate.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/screens/photo_vault_screen.dart';
import 'package:mimic/vault/screens/vault_home_screen.dart';
import 'package:mimic/vault/screens/video_vault_screen.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/security/vault_ui_access.dart';
import 'package:mimic/vault/services/background_import_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/import_coordinator.dart';
import 'package:mimic/vault/services/import_journal_store.dart';
import 'package:mimic/vault/services/media_import_policy.dart';
import 'package:mimic/vault/services/media_picker_adapter.dart';
import 'package:mimic/vault/services/video_vault_service.dart';

class _WidgetPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;
  final String tempPath;

  _WidgetPathProvider({required this.docsPath, required this.tempPath});

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

class _FastWidgetCrypto extends Fake
    with ChangeNotifier
    implements VaultCrypto {
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
    if (oldKey != null) oldKey.fillRange(0, oldKey.length, 0);
    scheduleMicrotask(notifyListeners);
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
    final out = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
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
  Future<BlobIntegrityStatus> verifyFileIntegrity(File file) =>
      verifyFileIntegrityControlled(file);

  @override
  Future<BlobIntegrityStatus> verifyFileIntegrityControlled(
    File file, {
    void Function(int bytesProcessed)? onBytesProgress,
    bool Function()? shouldAbort,
    CryptoIsolateCancelHandle? cancelHandle,
  }) async {
    if ((shouldAbort != null && shouldAbort()) ||
        (cancelHandle != null && cancelHandle.isCancelled)) {
      throw const OperationCancelledException();
    }
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
      onBytesProgress?.call(bytes.length);
      return BlobIntegrityStatus.healthy;
    } on BlobAuthenticationException {
      return BlobIntegrityStatus.tamperedOrCorrupted;
    }
  }
}

class _FakeUiPickerAdapter implements MediaPickerAdapter {
  final Map<ImportMediaKind, List<MediaSourceRef>> queuedPicks = {};
  final Map<String, File> files = {};
  int? observedMaxAssets;
  bool deleteOriginalConfirmed = false;
  int deleteCalls = 0;

  @override
  Future<PermissionState> requestPermission(ImportMediaKind kind) async =>
      PermissionState.authorized;

  @override
  Future<List<MediaSourceRef>?> pickAssets(
    BuildContext context, {
    required ImportMediaKind kind,
    int maxAssets = kMaxMediaImportSelection,
  }) async {
    observedMaxAssets = maxAssets;
    return queuedPicks[kind] ?? const [];
  }

  @override
  Future<ResolvedMediaSource> resolveSource(MediaSourceRef ref) async {
    final f = files[ref.sourceAssetId];
    if (f == null || !f.existsSync()) {
      return ResolvedMediaSource.unavailable(
        status: MediaSourceResolutionStatus.missing,
        mimeType: ref.mimeType,
        displayName: ref.displayName,
        errorCode: 'source_missing',
      );
    }
    return ResolvedMediaSource.ready(
      localFilePath: f.path,
      mimeType: ref.mimeType,
      displayName: ref.displayName,
      durationSeconds: ref.durationSeconds,
      sizeBytes: f.lengthSync(),
    );
  }

  @override
  Future<MediaDeleteResult> deleteOriginals(List<String> assetIds) async {
    deleteCalls++;
    if (!deleteOriginalConfirmed) {
      return MediaDeleteResult(
        deletedIds: const <String>{},
        keptIds: assetIds.toSet(),
      );
    }
    return MediaDeleteResult(
      deletedIds: assetIds.toSet(),
      keptIds: const <String>{},
    );
  }
}

final Uint8List _validPng1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory docsDir;
  late Directory tempDir;
  late Directory dbDir;
  late Directory sourceDir;
  late PathProviderPlatform originalPathProvider;
  late String originalDbPath;

  final Uint8List keyBytes = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 19 + 5) & 0xFF),
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
    SharedPreferences.setMockInitialValues({
      'pro_offers_enabled': false,
      'vault_manual_seen': true,
      'import_move_warning_ack': true,
    });
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
    tempRoot = await Directory.systemTemp.createTemp('mimic_nav_life_');
    docsDir = Directory(p.join(tempRoot.path, 'docs'))..createSync();
    tempDir = Directory(p.join(tempRoot.path, 'temp'))..createSync();
    dbDir = Directory(p.join(tempRoot.path, 'dbs'))..createSync();
    sourceDir = Directory(p.join(tempRoot.path, 'gallery'))..createSync();

    PathProviderPlatform.instance = _WidgetPathProvider(
      docsPath: docsDir.path,
      tempPath: tempDir.path,
    );
    await databaseFactory.setDatabasesPath(dbDir.path);
  });

  tearDown(() async {
    AutoLock().resetClockForTesting();
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

  List<MediaSourceRef> seedSources(
    _FakeUiPickerAdapter adapter, {
    required ImportMediaKind kind,
    required int count,
    String prefix = 'item',
  }) {
    final refs = <MediaSourceRef>[];
    for (var i = 0; i < count; i++) {
      final id = '${prefix}_$i';
      final name = kind == ImportMediaKind.photo ? '$id.png' : '$id.mp4';
      final f = File(p.join(sourceDir.path, name))
        ..writeAsBytesSync(_validPng1x1);
      adapter.files[id] = f;
      refs.add(
        MediaSourceRef(
          sourceAssetId: id,
          kind: kind,
          displayName: name,
          mimeType: kind == ImportMediaKind.photo ? 'image/png' : 'video/mp4',
          durationSeconds: kind == ImportMediaKind.video ? 3 : 0,
          expectedSizeBytes: _validPng1x1.length,
        ),
      );
    }
    adapter.queuedPicks[kind] = refs;
    return refs;
  }

  Future<void> pumpUntilSettled(
    WidgetTester tester,
    ImportCoordinator coordinator,
  ) async {
    for (var round = 0; round < 1000 && coordinator.isWorking; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  group('Screen Navigation, App-Scoped Coordinator & Fake-Time Security', () {
    testWidgets(
      'picks 12 items (> 9), survives video -> photo -> video & route pop/reopen while blocked without duplicate or lost state',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;

        var firstEncryptEntered = false;
        final allowFinish = Completer<void>();

        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
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
                firstEncryptEntered = true;
                await allowFinish.future;
              },
            ),
          );
          await coordinator.syncAfterUnlock();
          seedSources(
            picker,
            kind: ImportMediaKind.video,
            count: 12,
            prefix: 'v',
          );
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: MaterialApp(
              navigatorKey: router.navigatorKey,
              initialRoute: '/vault-home',
              routes: {
                '/vault-home': (_) => const VaultHomeScreen(),
                '/vault-photos': (_) => const PhotoVaultScreen(),
                '/vault-videos': (_) => const VideoVaultScreen(),
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Open VideoVaultScreen -> trigger import (12 items!)
        Navigator.of(
          tester.element(find.byType(VaultHomeScreen)),
        ).pushNamed('/vault-videos');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.tap(find.byType(FloatingActionButton));
        for (var round = 0; round < 60 && !firstEncryptEntered; round++) {
          await tester.runAsync(() async {
            for (var i = 0; i < 10 && !firstEncryptEntered; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(firstEncryptEntered, isTrue);
        await tester.pump();

        expect(picker.observedMaxAssets, 100);
        expect(find.textContaining('Importing '), findsOneWidget);

        // Navigate repeatedly: video -> photo -> video -> home -> photo -> video
        Navigator.of(
          tester.element(find.byType(VideoVaultScreen)),
        ).pushReplacementNamed('/vault-photos');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          find.descendant(
            of: find.byType(PhotoVaultScreen),
            matching: find.byKey(const ValueKey('import_activity_button')),
          ),
          findsOneWidget,
        );

        Navigator.of(
          tester.element(find.byType(PhotoVaultScreen)),
        ).pushReplacementNamed('/vault-videos');
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          find.descendant(
            of: find.byType(VideoVaultScreen),
            matching: find.byKey(const ValueKey('import_activity_button')),
          ),
          findsOneWidget,
        );

        // Pop VideoVaultScreen completely back to VaultHomeScreen while STILL blocked
        Navigator.of(tester.element(find.byType(VideoVaultScreen))).pop();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(VideoVaultScreen), findsNothing);
        expect(
          find.byKey(const ValueKey('home_import_activity_button')),
          findsOneWidget,
        );

        // Release barrier while vault screen is NOT even mounted
        allowFinish.complete();
        await pumpUntilSettled(tester, coordinator);
        expect(
          coordinator.isWorking,
          isFalse,
          reason:
              'Expected queue settled; pause=${coordinator.pauseReason}, jobs=${coordinator.jobs.map((j) => '${j.enqueueOrder}:${j.state.name}:${j.errorCode}').toList()}',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Reopen VideoVaultScreen -> all 12 committed & visible, zero lost state!
        Navigator.of(
          tester.element(find.byType(VaultHomeScreen)),
        ).pushNamed('/vault-videos');
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final savedVideos = await tester.runAsync(
          () => videoVault.getAllVideos(),
        );
        expect(savedVideos!.length, 12);

        await tester.runAsync(() async {
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
        // Flush VaultHomeScreen timers cleanly
        await tester.pump(const Duration(seconds: 6));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    testWidgets(
      'background grace exempts active import while requiring PIN UI re-authentication',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;
        var entered = false;
        final release = Completer<void>();

        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
          coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                entered = true;
                await release.future;
              },
            ),
          );
          await coordinator.syncAfterUnlock();
          seedSources(
            picker,
            kind: ImportMediaKind.photo,
            count: 2,
            prefix: 'bg',
          );
          await coordinator.enqueueBatch(
            sources: picker.queuedPicks[ImportMediaKind.photo]!,
            scope: const VaultImportScope(),
          );
          for (var i = 0; i < 200 && !entered; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(entered, isTrue);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: MaterialApp(
              navigatorKey: router.navigatorKey,
              initialRoute: '/vault-photos',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-photos': (_) => const PhotoVaultScreen(),
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Real photo screen exposes active import pill while batch runs.
        expect(
          find.byKey(const ValueKey('import_activity_button')),
          findsOneWidget,
        );
        expect(find.textContaining('Importing '), findsOneWidget);

        // Background exemption check while active: keeps crypto unlocked for
        // worker, while UI access requires re-authentication after background grace!
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
        AutoLock().setBackgroundedAtForTesting(
          DateTime.now().subtract(const Duration(seconds: 75)),
        );
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(crypto.isUnlocked, isTrue);
        expect(find.text('PIN_SCREEN'), findsOneWidget);

        release.complete();
        await pumpUntilSettled(tester, coordinator);
        await tester.runAsync(() async {
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'fake-time idle exemption, 30-minute security ceiling lock, and AutoLockLease epoch safety',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;

        var enteredEncrypt = false;
        final releaseEncrypt = Completer<void>();

        late BuildContext capturedContext;
        late WidgetRef capturedRef;
        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
          coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            storageProbe: () async => 500 * 1024 * 1024,
            stageHooks: ImportCoordinatorStageHooks(
              onBeforeEncrypt: (_) async {
                enteredEncrypt = true;
                await releaseEncrypt.future;
              },
            ),
          );
          await coordinator.syncAfterUnlock();
          seedSources(
            picker,
            kind: ImportMediaKind.photo,
            count: 2,
            prefix: 'f',
          );
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: MaterialApp(
              navigatorKey: router.navigatorKey,
              initialRoute: '/vault-home',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-home': (_) => Consumer(
                  builder: (context, ref, _) {
                    capturedContext = context;
                    capturedRef = ref;
                    AutoLock().init(context, ref);
                    return const VaultHomeScreen();
                  },
                ),
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Prove epoch-scoped AutoLockLease from session N cannot release session N+1 lease:
        final oldLease = AutoLock().acquireProtectedOperation();
        expect(AutoLock().protectedOperationCount, 1);
        AutoLock().init(capturedContext, capturedRef);
        expect(AutoLock().protectedOperationCount, 0);
        final newLease = AutoLock().acquireProtectedOperation();
        expect(AutoLock().protectedOperationCount, 1);
        oldLease.release(); // Must be a no-op!
        expect(AutoLock().protectedOperationCount, 1);
        newLease.release();
        expect(AutoLock().protectedOperationCount, 0);

        var fakeClock = DateTime(2026, 1, 1, 12, 0, 0);
        AutoLock().setNowForTesting(() => fakeClock);

        // Start import (acquires coordinator ImportAuthorizationLease while blocked inside worker)
        await tester.runAsync(() async {
          await coordinator.enqueueBatch(
            sources: picker.queuedPicks[ImportMediaKind.photo]!,
            scope: const VaultImportScope(),
          );
          for (var i = 0; i < 200 && !enteredEncrypt; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(enteredEncrypt, isTrue);
        expect(AutoLock().hasActiveImportAuthorization, isTrue);
        expect(coordinator.hasActiveImportLeaseForTest, isTrue);

        // 6 minutes foreground UI idle: UI browsing locks behind PIN_SCREEN,
        // while background import authorization keeps running until ceiling!
        fakeClock = fakeClock.add(const Duration(minutes: 6));
        await tester.pump(const Duration(minutes: 6));
        await tester.pump(const Duration(milliseconds: 400));
        expect(crypto.isUnlocked, isTrue);
        expect(find.text('PIN_SCREEN'), findsOneWidget);

        // Advance fakeClock past 30-minute ceiling and evaluate watchdog:
        // MUST revoke import auth, lock DEK, & pause import safely.
        fakeClock = fakeClock.add(const Duration(minutes: 25));
        await tester.runAsync(() async {
          AutoLock().checkImportWatchdogsNow();
          for (var i = 0; i < 100 && coordinator.isWorking; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        AutoLock().resetClockForTesting();

        expect(crypto.isUnlocked, isFalse);
        expect(coordinator.isWorking, isFalse);
        expect(AutoLock().hasActiveImportAuthorization, isFalse);
        expect(find.text('PIN_SCREEN'), findsOneWidget);

        releaseEncrypt.complete();
        await tester.pump(const Duration(seconds: 12));

        await tester.runAsync(() async {
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 12));
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );

    testWidgets(
      'controls in details sheet (Retry, Cancel, Clear finished) and conceal teardown work without leaks',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;

        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
          coordinator = ImportCoordinator(
            crypto: crypto,
            platformService: platform,
            fileVault: fileVault,
            videoVault: videoVault,
            pickerAdapter: picker,
            journal: journal,
            storageProbe: () async => 500 * 1024 * 1024,
          );
          await coordinator.syncAfterUnlock();
          final missing = const MediaSourceRef(
            sourceAssetId: 'missing_item',
            kind: ImportMediaKind.photo,
            displayName: 'missing_item.png',
            mimeType: 'image/png',
          );
          final okRefs = seedSources(
            picker,
            kind: ImportMediaKind.photo,
            count: 1,
            prefix: 'ok',
          );
          await coordinator.enqueueBatch(
            sources: [missing, ...okRefs],
            scope: const VaultImportScope(),
          );
          for (var i = 0; i < 200; i++) {
            if (!coordinator.isWorking &&
                coordinator.jobs.every(
                  (j) =>
                      j.state == ImportJobState.needsSource ||
                      j.state == ImportJobState.savedOriginalKept,
                )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: const MaterialApp(home: PhotoVaultScreen()),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Import finished — 1 not imported'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('import_activity_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Needs source'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Clear finished'), findsOneWidget);

        // Provide the previously missing file and tap Retry in the sheet!
        await tester.runAsync(() async {
          final recoveredFile = File(p.join(sourceDir.path, 'missing_item.png'))
            ..writeAsBytesSync(_validPng1x1);
          picker.files['missing_item'] = recoveredFile;
        });

        await tester.tap(find.text('Retry'));
        await tester.pump(const Duration(milliseconds: 20));
        await pumpUntilSettled(tester, coordinator);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.text('Clear finished'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(coordinator.jobs, isEmpty);

        // Test tearDownForConceal freezes and clears active protection cleanly
        AutoLock().tearDownForConceal();
        expect(AutoLock().protectedOperationCount, 0);
        expect(AutoLock().hasActiveImportAuthorization, isFalse);

        await tester.runAsync(() async {
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'background conceal covers vault immediately, UI timeout requires re-auth without interrupting worker, and re-auth reconnects to running queue',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;
        final bridge = _FakeNavBridge();
        var item2Blocked = false;
        final releaseItem2 = Completer<void>();
        var idx = 0;

        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
          seedSources(
            picker,
            kind: ImportMediaKind.photo,
            count: 3,
            prefix: 'reauth',
          );
          coordinator = ImportCoordinator(
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
                idx++;
                if (idx == 2) {
                  item2Blocked = true;
                  await releaseItem2.future;
                }
              },
            ),
          );
          await coordinator.syncAfterUnlock();
        });

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: MaterialApp(
              navigatorKey: router.navigatorKey,
              initialRoute: '/vault-photos',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-photos': (_) => Consumer(
                  builder: (context, ref, _) {
                    capturedRef = ref;
                    return const PhotoVaultScreen();
                  },
                ),
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
            ),
          ),
        );
        await tester.pump();
        AutoLock().init(
          tester.element(find.byType(PhotoVaultScreen)),
          capturedRef,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        await tester.runAsync(() async {
          await coordinator.enqueueBatch(
            sources: picker.queuedPicks[ImportMediaKind.photo]!,
            scope: const VaultImportScope(),
          );
          for (var i = 0; i < 200 && !item2Blocked; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(item2Blocked, isTrue);

        // Background transition -> privacy shield immediately covers PhotoVaultScreen UI!
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(find.byType(PhotoVaultScreen), findsOneWidget);
        expect(
          find.byType(FloatingActionButton),
          findsNothing,
          reason:
              'Background privacy shield must conceal vault controls immediately',
        );

        // Quick return (< 1m): privacy cover lifts without demanding PIN
        AutoLock().setBackgroundedAtForTesting(
          DateTime.now().subtract(const Duration(seconds: 15)),
        );
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.byType(FloatingActionButton), findsOneWidget);

        // Long return (> 1m): UI routes to PIN_SCREEN, while active batch & FGS keep running!
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
        AutoLock().setBackgroundedAtForTesting(
          DateTime.now().subtract(const Duration(seconds: 75)),
        );
        AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('PIN_SCREEN'), findsOneWidget);
        expect(crypto.isUnlocked, isTrue);
        expect(coordinator.hasActiveImportLeaseForTest, isTrue);
        expect(bridge.stopCount, 0);

        // Genuine re-auth restores UI access without duplicating or resetting item 2!
        capturedRef.read(vaultUiAccessProvider).restoreUiAccessAfterAuth();
        AutoLock.navigatorKey.currentState?.pushReplacementNamed(
          '/vault-photos',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(PhotoVaultScreen), findsOneWidget);

        releaseItem2.complete();
        await pumpUntilSettled(tester, coordinator);
        final saved = await tester.runAsync(() => fileVault.getAllPhotos());
        expect(saved!.length, 3);
        expect(bridge.stopCount, greaterThanOrEqualTo(1));

        await tester.runAsync(() async {
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'explicit security actions (lock, conceal, duress) immediately revoke background import authorization & wipe key',
      (tester) async {
        late AndroidPlatformService platform;
        late _FastWidgetCrypto crypto;
        late FileVaultService fileVault;
        late VideoVaultService videoVault;
        late _FakeUiPickerAdapter picker;
        late ImportJournalStore journal;
        late ImportCoordinator coordinator;
        final bridge = _FakeNavBridge();
        var entered = false;
        final release = Completer<void>();

        await tester.runAsync(() async {
          platform = AndroidPlatformService();
          crypto = _FastWidgetCrypto()..unlockWithKey(keyBytes);
          fileVault = FileVaultService(platform, crypto);
          videoVault = VideoVaultService(platform, crypto);
          picker = _FakeUiPickerAdapter();
          journal = ImportJournalStore(crypto);
          seedSources(
            picker,
            kind: ImportMediaKind.photo,
            count: 2,
            prefix: 'sec',
          );
          coordinator = ImportCoordinator(
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
                entered = true;
                await release.future;
              },
            ),
          );
          await coordinator.syncAfterUnlock();
        });

        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformServiceProvider.overrideWithValue(platform),
              vaultCryptoProvider.overrideWith((ref) => crypto),
              fileVaultServiceProvider.overrideWithValue(fileVault),
              videoVaultServiceProvider.overrideWithValue(videoVault),
              mediaPickerAdapterProvider.overrideWithValue(picker),
              importJournalStoreProvider.overrideWithValue(journal),
              backgroundImportBridgeProvider.overrideWithValue(bridge),
              importCoordinatorProvider.overrideWith((ref) => coordinator),
            ],
            child: MaterialApp(
              navigatorKey: router.navigatorKey,
              initialRoute: '/vault-photos',
              routes: {
                '/': (_) => const Scaffold(body: Text('GAME_HOME')),
                '/vault-photos': (_) => Consumer(
                  builder: (context, ref, _) {
                    capturedRef = ref;
                    return const PhotoVaultScreen();
                  },
                ),
                '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
              },
            ),
          ),
        );
        await tester.pump();
        AutoLock().init(
          tester.element(find.byType(PhotoVaultScreen)),
          capturedRef,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        await tester.runAsync(() async {
          await coordinator.enqueueBatch(
            sources: picker.queuedPicks[ImportMediaKind.photo]!,
            scope: const VaultImportScope(),
          );
          for (var i = 0; i < 200 && !entered; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(entered, isTrue);
        expect(AutoLock().hasActiveImportAuthorization, isTrue);

        // Trigger explicit security action (e.g. duress_pin / manual lock / panic)
        AutoLock().revokeAllAndLock(
          reason: 'duress_pin',
          fallbackCrypto: crypto,
        );
        await tester.pump();

        expect(crypto.isUnlocked, isFalse);
        expect(coordinator.isWorking, isFalse);
        expect(AutoLock().hasActiveImportAuthorization, isFalse);
        expect(bridge.stopCount, greaterThanOrEqualTo(1));

        release.complete();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await journal.close();
          coordinator.dispose();
          await fileVault.closeDatabase();
          await videoVault.closeDatabase();
        });
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  });
}

class _FakeNavBridge implements BackgroundImportBridge {
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<bool> hasNotificationPermission() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<BackgroundServiceStartResult> startImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {
    startCount++;
    return const BackgroundServiceStartResult(
      started: true,
      notificationsGranted: true,
    );
  }

  @override
  Future<void> updateImportService({
    required int completed,
    required int total,
    int? activePercent,
  }) async {}

  @override
  Future<void> stopImportService() async {
    stopCount++;
  }

  @override
  void setCommandHandler(
    void Function(BackgroundImportCommand command)? handler,
  ) {}

  @override
  void dispose() {}
}
