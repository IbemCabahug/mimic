import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/security/decoy_vault_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> secureRead(String key) async => _storage[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(_storage);

  @override
  Future<void> secureWrite(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteFile(String path) async {}

  @override
  bool isWeb() => false;

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DecoyVaultService Tests', () {
    late FakePlatformService fakePlatform;
    late DecoyVaultService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakePlatform = FakePlatformService();
      service = DecoyVaultService(fakePlatform);
    });

    test('isDecoyPinEnabled is false initially', () async {
      expect(await service.isDecoyPinEnabled(), isFalse);
    });

    test('setDecoyPin sets PBKDF2 hash and enables decoy PIN', () async {
      await service.setDecoyPin('4321');
      expect(await service.isDecoyPinEnabled(), isTrue);
      expect(await service.isDecoyPin('4321'), isTrue);
      expect(await service.isDecoyPin('0000'), isFalse);
      expect(await service.isDecoyPin('432'), isFalse);
    });

    test('clearDecoyPin removes decoy PIN and clears content', () async {
      await service.setDecoyPin('5678');
      expect(await service.isDecoyPinEnabled(), isTrue);

      await service.clearDecoyPin();
      expect(await service.isDecoyPinEnabled(), isFalse);
      expect(await service.isDecoyPin('5678'), isFalse);
    });

    test('starts with empty photos, notes, and documents by default', () async {
      final photos = await service.getPhotos();
      expect(photos, isEmpty);

      final notes = await service.getNotes();
      expect(notes, isEmpty);

      final docs = await service.getDocuments();
      expect(docs, isEmpty);
    });

    test('adds and deletes decoy photo', () async {
      final initialCount = (await service.getPhotos()).length;
      expect(initialCount, equals(0));
      final newPhoto = DecoyPhoto(
        id: 'test_photo_1',
        title: 'Botanical Garden',
        caption: 'Orchids and ferns',
        tags: ['#Nature'],
        createdAt: DateTime.now(),
      );

      await service.addPhoto(newPhoto);
      final afterAdd = await service.getPhotos();
      expect(afterAdd.length, equals(1));
      expect(afterAdd.first.id, equals('test_photo_1'));

      await service.deletePhoto('test_photo_1');
      final afterDelete = await service.getPhotos();
      expect(afterDelete.length, equals(0));
    });

    test('saves and deletes decoy note', () async {
      final note = DecoyNote(
        id: 'test_note_1',
        title: 'Secret Recipe',
        content: 'Flour, water, yeast, salt',
        tags: ['#Food'],
        updatedAt: DateTime.now(),
      );

      await service.saveNote(note);
      final notes = await service.getNotes();
      expect(notes.any((n) => n.id == 'test_note_1'), isTrue);

      await service.deleteNote('test_note_1');
      final notesAfter = await service.getNotes();
      expect(notesAfter.any((n) => n.id == 'test_note_1'), isFalse);
    });

    test('gates Decoy PIN and enabled state by Pro entitlement', () async {
      final proService = ProStatusService(fakePlatform, billingEnforced: true);
      final proGatedService = DecoyVaultService(fakePlatform, proService);

      // 1. User is not Pro initially
      expect(await proService.isPro(), isFalse);
      await proGatedService.setDecoyPin('9999');

      // Hash is saved in storage
      expect(await proGatedService.hasStoredDecoyPin(), isTrue);
      expect(await proGatedService.hasStoredDecoyPinMatch('9999'), isTrue);

      // But feature is NOT enabled and PIN does NOT authenticate because not Pro!
      expect(await proGatedService.isDecoyPinEnabled(), isFalse);
      expect(await proGatedService.isDecoyPin('9999'), isFalse);

      // 2. User upgrades to Pro
      await proService.grantPro();
      expect(await proService.isPro(), isTrue);
      expect(await proGatedService.isDecoyPinEnabled(), isTrue);
      expect(await proGatedService.isDecoyPin('9999'), isTrue);

      // 3. User revokes Pro tier
      await proService.revokePro();
      expect(await proService.isPro(), isFalse);

      // Decoy PIN must IMMEDIATELY stop working!
      expect(await proGatedService.isDecoyPinEnabled(), isFalse);
      expect(await proGatedService.isDecoyPin('9999'), isFalse);

      // Collision detection still detects the dormant pin
      expect(await proGatedService.hasStoredDecoyPinMatch('9999'), isTrue);
    });
  });
}
