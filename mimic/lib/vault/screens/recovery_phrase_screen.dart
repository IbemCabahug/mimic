import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import '../crypto/vault_crypto.dart';
import '../crypto/recovery_phrase.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class RecoveryPhraseScreen extends ConsumerStatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  ConsumerState<RecoveryPhraseScreen> createState() => RecoveryPhraseScreenState();
}

class RecoveryPhraseScreenState extends ConsumerState<RecoveryPhraseScreen> {
  int _step = 1; // 1: Generate, 2: Confirm, 3: Saved
  List<String> _generatedWords = [];
  List<String> get generatedWords => _generatedWords;
  List<int> _confirmIndices = [];
  final List<TextEditingController> _confirmControllers = List.generate(3, (_) => TextEditingController());
  String? _errorMessage;

  @override
  void dispose() {
    for (var controller in _confirmControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _generatePhrase() {
    setState(() {
      _generatedWords = RecoveryPhrase.generate();
      _errorMessage = null;
    });
  }

  void _startConfirmation() {
    final random = Random();
    final indices = <int>{};
    while (indices.length < 3) {
      indices.add(random.nextInt(12));
    }
    _confirmIndices = indices.toList()..sort();

    for (var controller in _confirmControllers) {
      controller.clear();
    }
    setState(() {
      _step = 2;
      _errorMessage = null;
    });
  }

  void _verifyConfirmation() async {
    bool allValid = true;
    for (int i = 0; i < 3; i++) {
      final enteredWord = _confirmControllers[i].text.trim().toLowerCase();
      final expectedWord = _generatedWords[_confirmIndices[i]];
      if (enteredWord != expectedWord) {
        allValid = false;
        break;
      }
    }

    if (!allValid) {
      setState(() {
        _errorMessage = 'Incorrect words. Please verify your recovery phrase.';
      });
      return;
    }

    try {
      final crypto = ref.read(vaultCryptoProvider);
      await crypto.storeRecoveryBlob(_generatedWords);
      setState(() {
        _step = 3;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save recovery phrase: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VaultScaffold(
      title: 'Recovery Phrase',
      showLockButton: false,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            if (_step == 1) _buildGenerateStep(),
            if (_step == 2) _buildConfirmStep(),
            if (_step == 3) _buildSavedStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Icon(
          Icons.security_outlined,
          color: VaultColors.accent,
          size: 64,
        ),
        const SizedBox(height: 20),
        const Text(
          'Backup Your Vault',
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
          'Your recovery phrase is a list of 12 random words. If you forget your PIN, you can use it to regain access to your vault. Without it, your files are lost forever.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: VaultColors.textSecondary,
            fontFamily: 'Inter',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        if (_generatedWords.isEmpty) ...[
          ElevatedButton(
            onPressed: _generatePhrase,
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text(
              'Generate Recovery Phrase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
        ] else ...[
          _buildWordGrid(),
          const SizedBox(height: 32),
          _buildWarningCard(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _startConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: VaultColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text(
              "I've Written Them Down",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _generatePhrase,
            child: const Text(
              'Regenerate Phrase',
              style: TextStyle(
                color: VaultColors.textSecondary,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWordGrid() {
    List<Widget> rows = [];
    for (int i = 0; i < 12; i += 3) {
      rows.add(
        Row(
          children: [
            Expanded(child: _buildWordCard(i + 1, _generatedWords[i])),
            const SizedBox(width: 8),
            Expanded(child: _buildWordCard(i + 2, _generatedWords[i + 1])),
            const SizedBox(width: 8),
            Expanded(child: _buildWordCard(i + 3, _generatedWords[i + 2])),
          ],
        ),
      );
      if (i < 9) {
        rows.add(const SizedBox(height: 8));
      }
    }
    return Column(children: rows);
  }

  Widget _buildWordCard(int index, String word) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Text(
            '$index. ',
            style: const TextStyle(
              color: VaultColors.textTertiary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              fontFamily: 'Inter',
            ),
          ),
          Expanded(
            child: Text(
              word,
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
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CRITICAL WARNING',
                  style: TextStyle(
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Inter',
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Write these words down on paper in the correct order. Keep them offline and safe. They will not be shown again.',
                  style: TextStyle(
                    color: Color(0xFF5D4037),
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
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Confirm Recovery Phrase',
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
          'Please enter the corresponding words from your recovery phrase to confirm your backup.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: VaultColors.textSecondary,
            fontFamily: 'Inter',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        _buildVerificationFields(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: VaultColors.error,
              fontSize: 13,
              fontFamily: 'Inter',
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _verifyConfirmation,
          style: ElevatedButton.styleFrom(
            backgroundColor: VaultColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: const Text(
            'Confirm & Save',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            setState(() {
              _step = 1;
              _errorMessage = null;
            });
          },
          child: const Text(
            'Back to Phrase',
            style: TextStyle(
              color: VaultColors.textSecondary,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationFields() {
    return Column(
      children: List.generate(3, (i) {
        final wordNum = _confirmIndices[i] + 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
            controller: _confirmControllers[i],
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: VaultColors.textPrimary, fontFamily: 'Inter'),
            decoration: InputDecoration(
              labelText: 'Enter word #$wordNum',
              labelStyle: const TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
              filled: true,
              fillColor: VaultColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: VaultColors.accent),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSavedStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Icon(
          Icons.check_circle_outline_rounded,
          color: VaultColors.success,
          size: 72,
        ),
        const SizedBox(height: 24),
        const Text(
          'Recovery Phrase Saved!',
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
          'Your backup is complete. You can now recover your vault at any time using your 12-word recovery phrase if you ever forget your PIN.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: VaultColors.textSecondary,
            fontFamily: 'Inter',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: VaultColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: const Text(
            'Done',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
        ),
      ],
    );
  }
}
