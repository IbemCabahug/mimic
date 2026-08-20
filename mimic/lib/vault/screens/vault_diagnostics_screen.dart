// lib/vault/screens/vault_diagnostics_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/platform_service.dart';
import '../../core/theme/app_theme.dart';
import '../crypto/keystore_service.dart';
import '../crypto/vault_crypto.dart';
import '../crypto/vault_kdf.dart';
import '../security/auto_lock.dart';
import '../services/document_vault_service.dart';
import '../services/file_vault_service.dart';
import '../services/media_format_report.dart';
import '../services/video_vault_service.dart';
import '../widgets/vault_scaffold.dart';

class VaultDiagnosticsScreen extends ConsumerStatefulWidget {
  const VaultDiagnosticsScreen({super.key});

  @override
  ConsumerState<VaultDiagnosticsScreen> createState() => _VaultDiagnosticsScreenState();
}

class _VaultDiagnosticsScreenState extends ConsumerState<VaultDiagnosticsScreen> {
  bool _isRunning = false;
  String? _nativeStatus;
  int? _pbkdf2AsyncMs;
  int? _pbkdf2PointycastleMs;
  int? _secureReadMs;
  int? _keystoreUnwrapMs;
  bool _pbkdf2AsyncFailed = false;
  bool _pbkdf2PointycastleFailed = false;
  bool _secureReadFailed = false;
  bool _keystoreFailed = false;
  bool _keystoreUnavailable = false;
  String? _error;

  MediaFormatReport? _formatReport;
  bool _isCheckingFormats = false;
  String? _formatError;

  @override
  void initState() {
    super.initState();
    _updateNativeStatus();
    // M16: this screen is read, not tapped. Suspending the idle timer stops the
    // vault locking mid-read. Resumed in dispose. The 30-minute ceiling in
    // auto_lock.dart (decision D13) remains the backstop.
    AutoLock().suspend();
  }

  @override
  void dispose() {
    AutoLock().resume();
    super.dispose();
  }

  void _updateNativeStatus() {
    final status = isNativePbkdf2Verified;
    if (status == null) {
      _nativeStatus = 'not yet attempted';
    } else if (status == true) {
      _nativeStatus = 'Verified — native HMAC-SHA256 path active';
    } else {
      _nativeStatus = 'failed, using fallback';
    }
  }

  Future<void> _runDiagnostics() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _error = null;
    });

    try {
      final samplePassword = Uint8List.fromList(utf8.encode('diagnostics_pin'));
      final sampleSalt = Uint8List.fromList(utf8.encode('diagnostics_salt_bytes_16'));

      // 1. Benchmark derivePbkdf2Async (100,000 iterations)
      int? asyncMs;
      bool asyncFailed = false;
      try {
        final swAsync = Stopwatch()..start();
        await derivePbkdf2Async(
          samplePassword,
          sampleSalt,
          kPbkdf2Iterations,
          kDerivedKeyLength,
        );
        swAsync.stop();
        asyncMs = swAsync.elapsedMilliseconds;
      } catch (_) {
        asyncFailed = true;
      }

      _updateNativeStatus();

      // 2. Benchmark forced PointyCastle path (100,000 iterations)
      int? pointyMs;
      bool pointyFailed = false;
      try {
        final swPointy = Stopwatch()..start();
        await derivePbkdf2Async(
          samplePassword,
          sampleSalt,
          kPbkdf2Iterations,
          kDerivedKeyLength,
          native: (_, __, ___, ____) async => throw Exception('force fallback'),
        );
        swPointy.stop();
        pointyMs = swPointy.elapsedMilliseconds;
      } catch (_) {
        pointyFailed = true;
      }

      // 3. Benchmark secureRead of an existing key
      int? readMs;
      bool readFailed = false;
      try {
        final platform = ref.read(platformServiceProvider);
        final swRead = Stopwatch()..start();
        await platform.secureRead('vault_pin_hash');
        swRead.stop();
        readMs = swRead.elapsedMilliseconds;
      } catch (_) {
        readFailed = true;
      }

      // 4. Benchmark keystore unwrap (read-only — never provisions a key)
      int? unwrapMs;
      bool unwrapFailed = false;
      bool unavailable = false;
      try {
        final platform = ref.read(platformServiceProvider);
        final storedWrapped = await platform.secureRead('master_key_wrapped');
        if (storedWrapped != null && storedWrapped.startsWith('hw1:')) {
          final keystore = AndroidKeystoreService();
          final swUnwrap = Stopwatch()..start();
          await keystore.unwrap(storedWrapped.substring(4));
          swUnwrap.stop();
          unwrapMs = swUnwrap.elapsedMilliseconds;
        } else {
          unavailable = true;
        }
      } catch (_) {
        unwrapFailed = true;
      }

      if (mounted) {
        setState(() {
          _pbkdf2AsyncMs = asyncMs;
          _pbkdf2AsyncFailed = asyncFailed;
          _pbkdf2PointycastleMs = pointyMs;
          _pbkdf2PointycastleFailed = pointyFailed;
          _secureReadMs = readMs;
          _secureReadFailed = readFailed;
          _keystoreUnwrapMs = unwrapMs;
          _keystoreFailed = unwrapFailed;
          _keystoreUnavailable = unavailable;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _checkMediaFormats() async {
    if (_isCheckingFormats) return;
    setState(() {
      _isCheckingFormats = true;
      _formatError = null;
    });

    try {
      final videoService = ref.read(videoVaultServiceProvider);
      final fileService = ref.read(fileVaultServiceProvider);
      final docService = ref.read(documentVaultServiceProvider);
      final platform = ref.read(platformServiceProvider);

      final videos = await videoService.getAllVideos();
      final photos = await fileService.getAllPhotos();
      final docs = await docService.listDocuments();

      final videoIds = videos.map((v) => v.id).toList();
      final photoIds = photos.map((p) => p.id).toList();
      final docIds = docs.map((d) => d.id).toList();

      final report = await buildMediaFormatReport(
        videoIds: videoIds,
        photoIds: photoIds,
        documentIds: docIds,
        resolveBlob: platform.resolveVaultFile,
      );

      if (mounted) {
        setState(() {
          _formatReport = report;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _formatError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingFormats = false;
        });
      }
    }
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: VaultColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: VaultColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crypto = ref.watch(vaultCryptoProvider);
    if (!crypto.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final divider = Divider(
      height: 1,
      thickness: 1,
      color: VaultColors.textTertiary.withValues(alpha: 0.2),
    );

    return VaultScaffold(
      title: 'Diagnostics',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: VaultColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VaultColors.textTertiary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  _buildMetricRow('Native PBKDF2 Status', _nativeStatus ?? 'not yet attempted'),
                  divider,
                  _buildMetricRow(
                    'derivePbkdf2Async (100k iter)',
                    _pbkdf2AsyncFailed ? 'FAILED' : (_pbkdf2AsyncMs != null ? '$_pbkdf2AsyncMs ms' : '—'),
                  ),
                  divider,
                  _buildMetricRow(
                    'PointyCastle fallback (100k iter)',
                    _pbkdf2PointycastleFailed ? 'FAILED' : (_pbkdf2PointycastleMs != null ? '$_pbkdf2PointycastleMs ms' : '—'),
                  ),
                  divider,
                  _buildMetricRow(
                    'secureRead (vault_pin_hash)',
                    _secureReadFailed ? 'FAILED' : (_secureReadMs != null ? '$_secureReadMs ms' : '—'),
                  ),
                  divider,
                  _buildMetricRow(
                    'Keystore unwrap',
                    _keystoreUnavailable
                        ? 'not applicable — vault is not hardware-bound'
                        : (_keystoreFailed ? 'FAILED' : (_keystoreUnwrapMs != null ? '$_keystoreUnwrapMs ms' : '—')),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: VaultColors.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 16.0, bottom: 12.0),
              child: Text(
                'Running diagnostics performs two full key derivations and may take a while.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: VaultColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            ElevatedButton(
              onPressed: _isRunning ? null : _runDiagnostics,
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isRunning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Run',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: VaultColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VaultColors.textTertiary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  _buildMetricRow(
                    'Videos — safe to recover (c2)',
                    _formatReport != null ? '${_formatReport!.videos.ctrV2} of ${_formatReport!.videos.total}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Videos — tied to this phone (c1)',
                    _formatReport != null ? '${_formatReport!.videos.ctrV1}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Videos — not yet converted (v1)',
                    _formatReport != null ? '${_formatReport!.videos.cbcV1}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Videos — very old format',
                    _formatReport != null ? '${_formatReport!.videos.legacyNoHeader}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Videos — file missing or unreadable',
                    _formatReport != null ? '${_formatReport!.videos.missingFile}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Photos — current format (v1)',
                    _formatReport != null ? '${_formatReport!.photos.cbcV1} of ${_formatReport!.photos.total}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Photos — very old format',
                    _formatReport != null ? '${_formatReport!.photos.legacyNoHeader}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Photos — file missing or unreadable',
                    _formatReport != null ? '${_formatReport!.photos.missingFile}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Documents — current format (v1)',
                    _formatReport != null ? '${_formatReport!.documents.cbcV1} of ${_formatReport!.documents.total}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Documents — very old format',
                    _formatReport != null ? '${_formatReport!.documents.legacyNoHeader}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Documents — file missing or unreadable',
                    _formatReport != null ? '${_formatReport!.documents.missingFile}' : '—',
                  ),
                  divider,
                  _buildMetricRow(
                    'Notes',
                    'stored in the database, no format header',
                  ),
                ],
              ),
            ),
            if (_formatError != null) ...[
              const SizedBox(height: 16),
              Text(
                _formatError!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: VaultColors.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 16.0, bottom: 12.0),
              child: Text(
                'Format only. A file counted as safe has the right format, but this check does not open it or prove it still decrypts.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: VaultColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            ElevatedButton(
              onPressed: _isCheckingFormats ? null : _checkMediaFormats,
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCheckingFormats
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Check media formats',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
