// mimic/lib/vault/screens/set_decoy_pin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../crypto/vault_crypto.dart';
import '../security/decoy_vault_service.dart';
import '../security/duress_service.dart';
import '../services/pro_status_service.dart';
import '../widgets/paywall_sheet.dart';

class SetDecoyPinScreen extends ConsumerStatefulWidget {
  const SetDecoyPinScreen({super.key});

  @override
  ConsumerState<SetDecoyPinScreen> createState() => _SetDecoyPinScreenState();
}

class _SetDecoyPinScreenState extends ConsumerState<SetDecoyPinScreen> {
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _hasExistingPin = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkProAndExistingPin();
    });
  }

  Future<void> _checkProAndExistingPin() async {
    final isPro = await ref.read(proStatusServiceProvider).isPro();
    if (!isPro) {
      if (mounted) {
        showPaywallSheet(context);
      }
    }
    final enabled = await ref.read(decoyVaultServiceProvider).isDecoyPinEnabled();
    if (mounted) {
      setState(() => _hasExistingPin = enabled);
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    if (_hasExistingPin) {
      // ── Update Flow: Current PIN -> New PIN -> Confirm PIN ──
      final currentPin = _currentPinController.text.trim();
      final newPin = _pinController.text.trim();
      final confirmPin = _confirmController.text.trim();

      if (currentPin.isEmpty) {
        setState(() => _error = 'Please enter your current Decoy PIN');
        return;
      }
      if (newPin.length < 4) {
        setState(() => _error = 'New PIN must be at least 4 digits');
        return;
      }
      if (newPin != confirmPin) {
        setState(() => _error = 'PINs do not match');
        return;
      }
      if (newPin == currentPin) {
        setState(() => _error = 'New PIN must be different from current PIN');
        return;
      }

      setState(() => _isLoading = true);
      try {
        final isCurrentValid = await ref.read(decoyVaultServiceProvider).isDecoyPin(currentPin);
        if (!isCurrentValid) {
          if (mounted) {
            setState(() {
              _error = 'Incorrect current Decoy PIN';
              _isLoading = false;
            });
          }
          return;
        }

        // AUDIT-05: Prevent Decoy PIN from colliding with Vault Master PIN or Duress PIN
        final isMasterPin = await ref.read(vaultCryptoProvider).verifyPin(newPin);
        if (isMasterPin) {
          if (mounted) {
            setState(() {
              _error = 'This PIN is unavailable. Please choose a different PIN.';
              _isLoading = false;
            });
          }
          return;
        }

        final isDuressPin = await ref.read(duressServiceProvider).isFakePin(newPin);
        if (isDuressPin) {
          if (mounted) {
            setState(() {
              _error = 'This PIN is unavailable. Please choose a different PIN.';
              _isLoading = false;
            });
          }
          return;
        }

        await ref.read(decoyVaultServiceProvider).setDecoyPin(newPin);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Decoy PIN updated successfully'),
              backgroundColor: VaultColors.success,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'Failed to save Decoy PIN: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      // ── Setup Flow: New PIN -> Confirm PIN ──
      final pin = _pinController.text.trim();
      if (pin.length < 4) {
        setState(() => _error = 'PIN must be at least 4 digits');
        return;
      }

      if (!_showConfirm) {
        setState(() => _isLoading = true);
        try {
          // AUDIT-05: Prevent Decoy PIN from colliding with Vault Master PIN or Duress PIN
          final isMasterPin = await ref.read(vaultCryptoProvider).verifyPin(pin);
          if (isMasterPin) {
            if (mounted) {
              setState(() {
                _error = 'This PIN is unavailable. Please choose a different PIN.';
                _isLoading = false;
              });
            }
            return;
          }

          final isDuressPin = await ref.read(duressServiceProvider).isFakePin(pin);
          if (isDuressPin) {
            if (mounted) {
              setState(() {
                _error = 'This PIN is unavailable. Please choose a different PIN.';
                _isLoading = false;
              });
            }
            return;
          }

          if (mounted) {
            setState(() {
              _showConfirm = true;
              _error = null;
              _isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _error = 'Validation error: $e';
              _isLoading = false;
            });
          }
        }
        return;
      }

      final confirm = _confirmController.text.trim();
      if (pin != confirm) {
        setState(() => _error = 'PINs do not match');
        _confirmController.clear();
        return;
      }

      setState(() => _isLoading = true);
      try {
        await ref.read(decoyVaultServiceProvider).setDecoyPin(pin);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Decoy PIN saved successfully'),
              backgroundColor: VaultColors.success,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'Failed to save Decoy PIN: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Decoy PIN?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
            color: VaultColors.textPrimary,
          ),
        ),
        content: const Text(
          'This will disable the Decoy Vault. Entering this PIN will no longer open the ghost album.',
          style: TextStyle(fontFamily: 'Inter', color: VaultColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: VaultColors.error, fontFamily: 'Inter')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(decoyVaultServiceProvider).clearDecoyPin();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Decoy PIN removed'),
            backgroundColor: VaultColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: VaultColors.textTertiary, fontFamily: 'Inter'),
      counterText: '',
      filled: true,
      fillColor: VaultColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VaultColors.accent, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        title: Text(
          _hasExistingPin ? 'Change Decoy PIN' : 'Decoy Vault (Ghost Album)',
          style: const TextStyle(
            color: VaultColors.accent,
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VaultColors.accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VaultColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: VaultColors.accent.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: VaultColors.accent, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasExistingPin ? 'Modify Decoy PIN' : 'Plausible Deniability',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: VaultColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _hasExistingPin
                              ? 'Enter your current Decoy PIN to verify identity, then configure your new decoy vault PIN.'
                              : 'If coerced to open your vault, entering this Decoy PIN reveals a convincing, harmless secondary vault. You can add non-sensitive photos and notes to make it look authentic. Your real vault and master encryption key remain 100% untouched and locked.',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: VaultColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (_hasExistingPin) ...[
              // Current Decoy PIN
              const Text(
                'Current Decoy PIN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _DecoyPinDots(pin: _currentPinController.text, maxLength: 8),
              const SizedBox(height: 12),
              TextField(
                controller: _currentPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  letterSpacing: 4,
                  color: VaultColors.textPrimary,
                ),
                decoration: _inputDecoration('Enter Current Decoy PIN'),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              // New Decoy PIN
              const Text(
                'New Decoy PIN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _DecoyPinDots(pin: _pinController.text, maxLength: 8),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  letterSpacing: 4,
                  color: VaultColors.textPrimary,
                ),
                decoration: _inputDecoration('Enter New Decoy PIN'),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              // Confirm New Decoy PIN
              const Text(
                'Confirm New Decoy PIN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _DecoyPinDots(pin: _confirmController.text, maxLength: 8),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  letterSpacing: 4,
                  color: VaultColors.textPrimary,
                ),
                decoration: _inputDecoration('Confirm New Decoy PIN'),
                onChanged: (_) => setState(() => _error = null),
              ),
            ] else ...[
              // Setup Flow
              Text(
                _showConfirm ? 'Confirm Decoy PIN' : 'Enter Decoy PIN',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _showConfirm
                    ? 'Re-enter the same PIN to verify'
                    : 'Must be at least 4 digits, different from other vault PINs',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: VaultColors.textSecondary,
                ),
              ),
              if (!_showConfirm) ...[
                _DecoyPinDots(
                  pin: _pinController.text,
                  maxLength: 8,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    letterSpacing: 4,
                    color: VaultColors.textPrimary,
                  ),
                  decoration: _inputDecoration('Enter Decoy PIN'),
                  onChanged: (_) {
                    setState(() {
                      _error = null;
                      if (_showConfirm) {
                        _showConfirm = false;
                        _confirmController.clear();
                      }
                    });
                  },
                ),
              ] else ...[
                _DecoyPinDots(
                  pin: _confirmController.text,
                  maxLength: 8,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    letterSpacing: 4,
                    color: VaultColors.textPrimary,
                  ),
                  decoration: _inputDecoration('Re-enter your PIN to verify'),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _showConfirm = false;
                        _confirmController.clear();
                        _error = null;
                      });
                    },
                    child: const Text(
                      'Back to change PIN',
                      style: TextStyle(color: VaultColors.textSecondary, fontFamily: 'Inter'),
                    ),
                  ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VaultColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: VaultColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: VaultColors.error,
                          fontFamily: 'Inter',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _hasExistingPin
                          ? 'Update Decoy PIN'
                          : (_showConfirm ? 'Save Decoy PIN' : 'Next'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            if (_hasExistingPin) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _removePin,
                icon: const Icon(Icons.delete_outline, color: VaultColors.error),
                label: const Text(
                  'Remove Decoy PIN',
                  style: TextStyle(color: VaultColors.error, fontFamily: 'Inter'),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: VaultColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecoyPinDots extends StatelessWidget {
  final String pin;
  final int maxLength;

  const _DecoyPinDots({required this.pin, required this.maxLength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (index) {
        final filled = index < pin.length;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? VaultColors.accent : VaultColors.surface,
            border: Border.all(color: VaultColors.accent.withValues(alpha: 0.3)),
          ),
        );
      }),
    );
  }
}
