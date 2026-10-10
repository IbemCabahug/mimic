import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/services/storage_optimizer_service.dart';
import 'package:mimic/vault/screens/storage_optimizer_screen.dart';
import 'package:mimic/vault/screens/vault_theme_selector_screen.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';

class _FakeStorageOptimizerService implements StorageOptimizerService {
  @override
  FileVaultService get fileVaultService => throw UnimplementedError();

  @override
  VideoVaultService get videoVaultService => throw UnimplementedError();

  @override
  DocumentVaultService get docVaultService => throw UnimplementedError();

  @override
  Future<StorageOptimizationReport> analyzeVault({
    int largeFileThreshold = 20 * 1024 * 1024,
  }) async {
    return const StorageOptimizationReport(
      photosBytes: 0,
      videosBytes: 0,
      docsBytes: 0,
      totalBytes: 0,
      photoCount: 0,
      videoCount: 0,
      docCount: 0,
      largeFiles: [],
      duplicateGroups: [],
    );
  }

  @override
  Future<void> deleteOptimizableFile(OptimizableFile file) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageOptimizerScreen', () {
    testWidgets('displays storage usage and tabs', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageOptimizerServiceProvider.overrideWithValue(_FakeStorageOptimizerService()),
            isProProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: StorageOptimizerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Storage Optimizer'), findsOneWidget);
      expect(find.text('Vault Storage Used'), findsOneWidget);
      expect(find.text('Mimic Pro Feature'), findsOneWidget);
      expect(find.text('No Duplicate Files Found'), findsOneWidget);
    });
  });

  group('VaultThemeSelectorScreen', () {
    testWidgets('displays palettes and allows theme selection for Pro', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isProProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(home: VaultThemeSelectorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault Themes'), findsOneWidget);
      expect(find.text('Classic Violet'), findsOneWidget);
      expect(find.text('Deep Ocean'), findsOneWidget);
      expect(find.text('Soft Lavender'), findsOneWidget);
      expect(find.text('Forest Twilight'), findsOneWidget);
      expect(find.text('Vintage Archive'), findsOneWidget);

      // Tap Deep Ocean
      await tester.tap(find.text('Deep Ocean'));
      await tester.pumpAndSettle();

      expect(find.text('Applied theme: Deep Ocean'), findsOneWidget);
    });
  });
}
