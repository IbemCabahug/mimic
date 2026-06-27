// mimic/lib/vault/screens/pin_screen.dart
import 'dart:async';
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
import '../security/lockout_service.dart';
import '../crypto/keystore_service.dart';
import 'wiped_vault_screen.dart';
import 'recovery_phrase_screen.dart';
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
  Duration _remainingLockout = Duration.zero;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _crypto = ref.read(vaultCryptoProvider);
    _concealService = ref.read(vaultConcealServiceProvider);
    _checkCreateMode();
    _checkIfWiped();
    _loadWrongAttempts();
    _checkLockout();
  }

  Future<void> _checkLockout() async {
    final lockoutService = ref.read(lockoutServiceProvider);
    final remaining = await lockoutService.remainingLockout();
    if (mounted && remaining > Duration.zero) {
      setState(() {
        _remainingLockout = remaining;
        _error = 'Try again in ${_formatDuration(remaining)}';
      });
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final lockoutService = ref.read(lockoutServiceProvider);
      final remaining = await lockoutService.remainingLockout();
      if (mounted) {
        if (remaining <= Duration.zero) {
          timer.cancel();
          setState(() {
            _remainingLockout = Duration.zero;
            _error = null;
          });
        } else {
          setState(() {
            _remainingLockout = remaining;
            _error = 'Try again in ${_formatDuration(remaining)}';
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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

  Future<void> _createVault(String pin) async {
    setState(() => _isLoading = true);
    final navigator = Navigator.of(context);
    try {
      await _crypto.initialize(pin);
      
      if (mounted) {
        setState(() {
          _error = null;
          _wrongAttempts = 0;
          _remainingLockout = Duration.zero;
        });
        await ref.read(lockoutServiceProvider).reset();

        PanicMode().init(context, ref);
        AutoLock().init(context, ref);

        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => RecoveryPhraseScreen(
              forcedSetup: true,
              migrateAfter: _crypto.needsHardwareMigration,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Couldn\'t create vault, please try again';
          _isConfirming = false;
          _firstEnteredPin = '';
          _isLoading = false;
        });
        _pinController.clear();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticate([String? overridePin]) async {
    final lockoutService = ref.read(lockoutServiceProvider);
    final remaining = await lockoutService.remainingLockout();
    if (remaining > Duration.zero) {
      if (mounted) {
        setState(() {
          _remainingLockout = remaining;
          _error = 'Try again in ${_formatDuration(remaining)}';
        });
        _startLockoutTimer();
      }
      return;
    }

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
        } else {
          // Explicit return path for vault creation to avoid fall-through
          _createVault(pin);
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
          await ref.read(lockoutServiceProvider).reset();
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
            _remainingLockout = Duration.zero;
          });
          await ref.read(lockoutServiceProvider).reset();

          PanicMode().init(context, ref);
          AutoLock().init(context, ref);

          if (!_crypto.hasRecoveryPhrase) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (_) => RecoveryPhraseScreen(
                  forcedSetup: true,
                  migrateAfter: _crypto.needsHardwareMigration,
                ),
              ),
            );
          } else {
            if (_crypto.needsHardwareMigration) {
               try {
                 await _crypto.migrateToHardwareBinding();
               } catch (e) {
                 navigator.pushReplacement(
                   MaterialPageRoute(
                     builder: (_) => const RecoveryPhraseScreen(
                       forcedSetup: true,
                       migrateAfter: false,
                     ),
                   ),
                 );
                 return;
               }
            }
            navigator.pushReplacementNamed('/vault-home');
          }
        }
      } on KeystoreInvalidException catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 4)),
          );
          Navigator.of(context).pushNamed('/vault-enter-recovery');
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
            await ref.read(lockoutServiceProvider).setLockout(currentCount);
            if (mounted) setState(() => _wrongAttempts = currentCount);

            final newRemaining = await ref.read(lockoutServiceProvider).remainingLockout();
            if (newRemaining > Duration.zero && mounted) {
              setState(() {
                _remainingLockout = newRemaining;
                _error = 'Try again in ${_formatDuration(newRemaining)}';
              });
              _startLockoutTimer();
            } else if (mounted) {
              setState(() => _error = 'Invalid PIN');
            }
          } catch (ex) {
            debugPrint('Failed to save wrong attempts log: $ex');
            if (mounted) setState(() {
              _wrongAttempts++;
              _error = 'Invalid PIN';
            });
          }
        } else {
          if (mounted) setState(() {
            _wrongAttempts++;
            _error = 'Invalid PIN';
          });
        }
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
    _lockoutTimer?.cancel();
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
          _isCreateMode ? 'Set Up PIN' : 'Security',
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
                  ? (_isConfirming ? 'Confirm PIN' : 'Create PIN')
                  : 'Enter PIN',
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
              readOnly: _remainingLockout > Duration.zero,
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
                onDecoyAdmin: () {
                  if (mounted) {
                    Navigator.of(context).pushReplacementNamed('/admin-panel');
                  }
                },
                onError: (result) {
                  if (mounted) setState(() => _error = _biometricResultToMessage(result));
                },
              ),
            if (!kIsWeb && !_isCreateMode)
              const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_isLoading || _remainingLockout > Duration.zero) ? null : _authenticate,
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