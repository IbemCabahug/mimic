// lib/vault/screens/enter_recovery_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/vault_crypto.dart';
import '../crypto/recovery_phrase.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';
import 'reset_pin_screen.dart';

class EnterRecoveryScreen extends ConsumerStatefulWidget {
  const EnterRecoveryScreen({super.key});

  @override
  ConsumerState<EnterRecoveryScreen> createState() => _EnterRecoveryScreenState();
}

class _EnterRecoveryScreenState extends ConsumerState<EnterRecoveryScreen> {
  final List<TextEditingController> _controllers = List.generate(12, (_) => TextEditingController());
  final _scrollController = ScrollController();
  bool _isLoading = false;

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
    // Rebuilds the widget to update validation borders and the recover button state
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isButtonEnabled {
    return _controllers.every((c) => c.text.trim().isNotEmpty);
  }

  Future<void> _recoverVault() async {
    if (!_isButtonEnabled) return;

    setState(() {
      _isLoading = true;
    });

    final words = _controllers.map((c) => c.text.trim().toLowerCase()).toList();

    try {
      final crypto = ref.read(vaultCryptoProvider);
      final success = await crypto.recoverWithPhrase(words);

      if (success) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ResetPinScreen()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect recovery phrase'),
              backgroundColor: VaultColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: VaultColors.error,
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
      title: 'Recovery',
      showLockButton: false,
      body: SafeArea(
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Icon(
                  Icons.settings_backup_restore_outlined,
                  color: VaultColors.accent,
                  size: 64,
                ),
                const SizedBox(height: 16),
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
                  'Enter your 12 words in order',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: VaultColors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 32),
                ...List.generate(12, (index) {
                  final text = _controllers[index].text.trim().toLowerCase();
                  final bool isEmpty = text.isEmpty;
                  final bool isValid = !isEmpty && RecoveryPhrase.isValidWord(text);

                  Color borderValColor = isEmpty
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
                  onPressed: _isButtonEnabled && !_isLoading ? _recoverVault : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VaultColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Recover Vault',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Cancel',
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
        ),
      ),
    );
  }
}
