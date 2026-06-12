// mimic/lib/vault/screens/pin_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/vault_crypto.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/widgets/biometric_vault_unlock.dart';
import '../services/intruder_service.dart';
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../security/duress_service.dart';
import '../security/pin_wipe_service.dart';
import '../security/vault_conceal_service.dart';
import 'wiped_vault_screen.dart';
import 'package:mimic/core/providers/provider_registration.dart'
    show vaultConcealServiceProvider;

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final TextEditingController _pinController = TextEditingController();
  late final VaultCrypto _crypto;
  late final VaultConcealService _concealService;
  final IntruderService _intruderService = IntruderService();
  String? _error;
  bool _isLoading = false;
  int _wrongAttempts = 0;
  bool _isCreateMode = false;
  bool _isConfirming = false;
  String _firstEnteredPin = '';

  @override
  void initState() {
    super.initState();
    _crypto = ref.read(vaultCryptoProvider);
    // Pause the global conceal shake listener while the PIN screen is active
    // to avoid toggling conceal state during PIN entry.
    _concealService = ref.read(vaultConcealServiceProvider);
    _concealService.pauseShakeListening();
    _checkCreateMode();
    _checkIfWiped();
    _loadWrongAttempts();
  }

  Future<void> _checkCreateMode() async {
    final hash = await ref.read(platformServiceProvider).secureRead('vault_pin_hash');
    if (mounted) {
      setState(() {
        _isCreateMode = (hash == null || hash.isEmpty);
      });
    }
  }

  Future<void> _checkIfWiped() async {
    if (kIsWeb) return;
    final wiped = await ref.read(pinWipeServiceProvider).isPinWiped();
    if (wiped && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WipedVaultScreen()),
      );
    }
  }

  Future<void> _loadWrongAttempts() async {
    if (kIsWeb) return;
    try {
      final stored = await ref.read(platformServiceProvider).secureRead('wrong_attempts');
      final count = int.tryParse(stored ?? '') ?? 0;
      if (mounted) {
        setState(() => _wrongAttempts = count);
      }
    } catch (_) {}
  }

  Future<void> _authenticateWithSecret(String secret) async {
    await _authenticate(secret);
  }

  Future<void> _authenticate([String? overridePin]) async {
    final pin = overridePin ?? _pinController.text;
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your PIN');
      return;
    }

    if (_isCreateMode && overridePin == null) {
      if (pin.length < 4) {
        setState(() => _error = 'PIN must be at least 4 digits');
        return;
      }
      if (!_isConfirming) {
        setState(() {
          _firstEnteredPin = pin;
          _isConfirming = true;
          _error = null;
        });
        _pinController.clear();
        return;
      } else {
        if (pin != _firstEnteredPin) {
          setState(() {
            _error = 'PINs do not match. Please try again.';
            _isConfirming = false;
            _firstEnteredPin = '';
          });
          _pinController.clear();
          return;
        }
      }
    }

    final navigator = Navigator.of(context);
    setState(() => _isLoading = true);
    () async {
      try {
        final duressService = ref.read(duressServiceProvider);
        final isFakePin = await duressService.isFakePin(pin);

        if (isFakePin) {
          _pinController.clear();
          if (mounted) {
            setState(() {
              _error = null;
              _wrongAttempts = 0;
            });
            navigator.pushReplacementNamed('/admin-panel');
          }
          return;
        }

        // Conceal check runs AFTER duress so the decoy PIN still opens the
        // admin panel while concealed. Real PIN is denied silently.
        if (!_isCreateMode) {
          final concealed = await _concealService.isConcealed();
          if (concealed) {
            _pinController.clear();
            if (mounted) setState(() => _error = 'Invalid PIN');
            return;
          }
        }

        await _crypto.initialize(pin);
        if (!kIsWeb) {
          await ref.read(platformServiceProvider).secureWrite('vault_pin', pin);
          await ref.read(platformServiceProvider).secureWrite('wrong_attempts', '0');
          await ref.read(platformServiceProvider).secureWrite('vault_setup_completed', 'true');
        }

        if (mounted) {
          setState(() {
            _error = null;
            _wrongAttempts = 0;
          });

          PanicMode().init(context, ref);
          AutoLock().init(context, ref);

          navigator.pushReplacementNamed('/vault-home');
        }
      } catch (e) {
        if (!kIsWeb) {
          try {
            final stored = await ref.read(platformServiceProvider).secureRead('wrong_attempts');
            final currentCount = (int.tryParse(stored ?? '') ?? 0) + 1;
            if (currentCount % 3 == 0) {
              _intruderService.captureIntruder(_crypto);
            }
            await ref.read(platformServiceProvider).secureWrite('wrong_attempts', currentCount.toString());
            if (mounted) setState(() => _wrongAttempts = currentCount);
          } catch (ex) {
            debugPrint('Failed to save wrong attempts log: $ex');
            if (mounted) setState(() => _wrongAttempts++);
          }
        } else {
          if (mounted) setState(() => _wrongAttempts++);
        }
        if (mounted) setState(() => _error = 'Invalid PIN');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }();
  }

  String? _biometricResultToMessage(BiometricResult result) {
    switch (result) {
      case BiometricResult.unavailable:
        return 'Biometrics unavailable';
      case BiometricResult.notEnrolled:
        return 'No biometrics enrolled';
      case BiometricResult.lockedOut:
        return 'Biometrics locked out';
      case BiometricResult.error:
        return 'Biometric error';
      case BiometricResult.failed:
        return 'Biometric authentication failed';
      case BiometricResult.success:
        return null;
    }
  }

  @override
  void dispose() {
    // Resume the global conceal shake listener when leaving the PIN screen.
    _concealService.resumeShakeListening();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isCreateMode ? 'Vault Setup' : 'Vault Access',
          style: const TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isCreateMode
                  ? (_isConfirming ? 'Confirm Vault PIN' : 'Create Vault PIN')
                  : 'Enter Vault PIN',
              style: const TextStyle(
                color: Color(0xFF7F77DD),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '____',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x337F77DD)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x337F77DD)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF7F77DD)),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 24),
            if (!kIsWeb && !_isCreateMode)
              BiometricVaultUnlock(
                onUnlockedVault: (secret) => _authenticateWithSecret(secret),
                onUnlockedAdmin: (secret) => _authenticateWithSecret(secret),
                onError: (result) {
                  if (mounted) setState(() => _error = _biometricResultToMessage(result));
                },
              ),
            if (!kIsWeb && !_isCreateMode)
              const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _authenticate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F77DD),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  : Text(
                      _isCreateMode ? 'Create PIN' : 'Unlock',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
            if (_isCreateMode) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/vault-import');
                },
                child: const Text(
                  'Restore from Backup',
                  style: TextStyle(
                    color: Color(0xFF7F77DD),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
            if (!_isCreateMode && _wrongAttempts >= 3) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/vault-enter-recovery');
                },
                child: const Text(
                  'Forgot PIN?',
                  style: TextStyle(
                    color: Color(0xFF7F77DD),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}