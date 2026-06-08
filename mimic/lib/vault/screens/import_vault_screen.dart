import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:mimic/core/theme/app_theme.dart';
import 'package:mimic/vault/widgets/vault_scaffold.dart';
import 'package:mimic/vault/export/vault_importer.dart';
import 'package:mimic/vault/crypto/recovery_phrase.dart';

class ImportVaultScreen extends ConsumerStatefulWidget {
  const ImportVaultScreen({super.key});

  @override
  ConsumerState<ImportVaultScreen> createState() => _ImportVaultScreenState();
}

class _ImportVaultScreenState extends ConsumerState<ImportVaultScreen> {
  int _step = 1; // 1: Pick File, 2: Enter Phrase
  File? _selectedFile;
  String? _validationError;
  bool _isLoading = false;
  
  final List<TextEditingController> _controllers = List.generate(12, (_) => TextEditingController());
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    for (var controller in _controllers) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isImportButtonEnabled {
    return _controllers.every((c) => c.text.trim().isNotEmpty);
  }

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _validationError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final validation = await VaultImporter.validateFile(file);

        if (mounted) {
          if (validation.isValid) {
            setState(() {
              _selectedFile = file;
            });
            // Show checkmark briefly before transitioning
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) {
              setState(() {
                _step = 2;
              });
            }
          } else {
            setState(() {
              _validationError = validation.reason ?? 'Invalid backup file';
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validationError = 'Failed to pick or validate file: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _importVault() async {
    if (!_isImportButtonEnabled || _selectedFile == null) return;

    setState(() {
      _isLoading = true;
    });

    final words = _controllers.map((c) => c.text.trim().toLowerCase()).toList();

    try {
      final success = await VaultImporter.importWithPhrase(_selectedFile!, words);

      if (success) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/vault-reset-pin',
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Incorrect recovery phrase',
                style: TextStyle(fontFamily: 'Inter'),
              ),
              backgroundColor: VaultColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import failed: $e',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            backgroundColor: VaultColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: _step == 1 ? 'Import Vault' : 'Enter Recovery Phrase',
      showLockButton: false,
      body: Stack(
        children: [
          SafeArea(
            child: _step == 1 ? _buildStep1() : _buildStep2(),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: VaultColors.accent),
                    SizedBox(height: 16),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    final fileName = _selectedFile != null ? p.basename(_selectedFile!.path) : null;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.archive_outlined,
          color: VaultColors.accent,
          size: 72,
        ),
        const SizedBox(height: 24),
        const Text(
          'Import Vault',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: VaultColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Select a valid `.mimic` backup file to begin restoring your vault data. In the next step, you will be prompted for your recovery phrase.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: VaultColors.textSecondary,
            fontFamily: 'Inter',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        if (fileName != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VaultColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VaultColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: VaultColors.success, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      color: VaultColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Inter',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (_validationError != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VaultColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VaultColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: VaultColors.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INVALID BACKUP',
                        style: TextStyle(
                          color: VaultColors.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _validationError!,
                        style: TextStyle(
                          color: VaultColors.error.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontFamily: 'Inter',
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        ElevatedButton(
          onPressed: _isLoading ? null : _pickFile,
          style: ElevatedButton.styleFrom(
            backgroundColor: VaultColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: const Text(
            'Select .mimic file',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final fileName = _selectedFile != null ? p.basename(_selectedFile!.path) : '';

    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VaultColors.success.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VaultColors.success.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: VaultColors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Importing: $fileName',
                      style: const TextStyle(
                        color: VaultColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter Recovery Phrase',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: VaultColors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your 12 words in order to decrypt the backup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: VaultColors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 24),
            ...List.generate(12, (index) {
              final text = _controllers[index].text.trim().toLowerCase();
              final bool isEmpty = text.isEmpty;
              final bool isValid = !isEmpty && RecoveryPhrase.isValidWord(text);

              final Color borderValColor = isEmpty
                  ? const Color(0xFFE0E0E0)
                  : (isValid ? VaultColors.success : VaultColors.error);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _controllers[index],
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    labelText: 'Word ${index + 1}',
                    labelStyle: const TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
                    filled: true,
                    fillColor: VaultColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderValColor, width: isEmpty ? 1 : 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderValColor, width: isEmpty ? 1 : 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isEmpty ? VaultColors.accent : borderValColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isImportButtonEnabled && !_isLoading ? _importVault : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return VaultColors.accent.withValues(alpha: 0.3);
                  }
                  return VaultColors.accent;
                }),
              ),
              child: const Text(
                'Import Vault',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _step = 1;
                  _selectedFile = null;
                  _validationError = null;
                });
              },
              child: const Text(
                'Back',
                style: TextStyle(
                  color: VaultColors.textSecondary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
