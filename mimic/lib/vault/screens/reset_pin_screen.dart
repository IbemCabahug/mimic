// lib/vault/screens/reset_pin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/vault_crypto.dart';
import '../widgets/vault_scaffold.dart';
import '../../core/theme/app_theme.dart';

class ResetPinScreen extends ConsumerStatefulWidget {
  const ResetPinScreen({super.key});

  @override
  ConsumerState<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends ConsumerState<ResetPinScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  String _firstPin = '';
  String _currentInput = '';
  bool _isConfirmStep = false;
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _inputDigit(String digit) {
    if (_isLoading || _currentInput.length >= 6) return;

    setState(() {
      _currentInput += digit;
      _error = null;
    });

    if (_currentInput.length == 6) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        _handlePinSubmission();
      });
    }
  }

  void _backspace() {
    if (_isLoading || _currentInput.isEmpty) return;
    setState(() {
      _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      _error = null;
    });
  }

  void _clearAll() {
    if (_isLoading) return;
    setState(() {
      _currentInput = '';
      _error = null;
    });
  }

  void _handlePinSubmission() {
    if (!_isConfirmStep) {
      // Transition to confirmation step
      setState(() {
        _firstPin = _currentInput;
        _currentInput = '';
        _isConfirmStep = true;
      });
    } else {
      // Verify match
      if (_currentInput == _firstPin) {
        _saveNewPin(_currentInput);
      } else {
        // Mismatch — trigger shake animation
        _shakeController.forward(from: 0.0);
        setState(() {
          _currentInput = '';
          _firstPin = '';
          _isConfirmStep = false;
          _error = 'PINs do not match. Please try again.';
        });
        HapticFeedback.vibrate();
      }
    }
  }

  Future<void> _saveNewPin(String pin) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final crypto = ref.read(vaultCryptoProvider);
      
      // Update PIN
      await crypto.changePin(pin);
      
      // Store recovery blob with the new PIN
      await crypto.storeRecoveryBlob();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN updated and recovery phrase secured successfully'),
            backgroundColor: VaultColors.success,
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil('/vault-home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save new PIN: $e';
          _currentInput = '';
          _firstPin = '';
          _isConfirmStep = false;
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

  Widget _buildNumpadKey(String label, {VoidCallback? onTap, Widget? icon}) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: VaultColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: icon ?? Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: VaultColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpadRow(List<String> rowKeys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: rowKeys.map((key) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: key == 'clear'
                ? _buildNumpadKey(
                    '',
                    icon: const Icon(Icons.clear_all, color: VaultColors.textSecondary, size: 28),
                    onTap: _clearAll,
                  )
                : key == 'backspace'
                    ? _buildNumpadKey(
                        '',
                        icon: const Icon(Icons.backspace_outlined, color: VaultColors.textSecondary, size: 24),
                        onTap: _backspace,
                      )
                    : _buildNumpadKey(
                        key,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _inputDigit(key);
                        },
                      ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> offsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 15.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 15.0, end: -15.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -15.0, end: 15.0), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 15.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    return PopScope(
      canPop: false,
      child: VaultScaffold(
        title: 'Set New PIN',
        showBackButton: false,
        showLockButton: false,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: VaultColors.accent,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create New PIN',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: VaultColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _isConfirmStep
                        ? 'Re-enter your new PIN to confirm'
                        : 'Choose a new 6-digit PIN for your vault',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: VaultColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: offsetAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(offsetAnimation.value, 0.0),
                      child: child,
                    );
                  },
                  child: PinDotIndicator(
                    filledCount: _currentInput.length,
                    totalDots: 6,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: VaultColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_isLoading)
                  const SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: VaultColors.accent,
                      ),
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxWidth: 270),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        _buildNumpadRow(['1', '2', '3']),
                        _buildNumpadRow(['4', '5', '6']),
                        _buildNumpadRow(['7', '8', '9']),
                        _buildNumpadRow(['clear', '0', 'backspace']),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
