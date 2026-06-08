// mimic/lib/vault/screens/pin_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/vault_crypto.dart';
import '../../core/services/platform_service.dart';
import '../services/biometric_service.dart';
import '../services/intruder_service.dart';
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../security/duress_service.dart';
import '../security/shake_wipe_service.dart';
import '../security/pin_wipe_service.dart';
import 'wiped_vault_screen.dart';

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final TextEditingController _pinController = TextEditingController();
  late final VaultCrypto _crypto;
  final BiometricService _biometricService = BiometricService();
  final IntruderService _intruderService = IntruderService();
  String? _error;
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  int _wrongAttempts = 0;

  @override
  void initState() {
    super.initState();
    _crypto = ref.read(vaultCryptoProvider);
    _checkIfWiped();
    _checkBiometricState();
    _loadWrongAttempts();
  }

  Future<void> _checkIfWiped() async {
    if (kIsWeb) return;
    final wiped = await ref.read(pinWipeServiceProvider).isPinWiped();
    if (wiped && mounted) {
      await _setupShakeListener();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WipedVaultScreen()),
      );
    } else {
      _setupShakeListener();
    }
  }

  Future<void> _setupShakeListener() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final shakeEnabled = prefs.getBool('shake_wipe_enabled') ?? false;
    if (shakeEnabled) {
      ref.read(shakeWipeServiceProvider).startListening(() async {
        await ref.read(pinWipeServiceProvider).wipePin();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WipedVaultScreen()),
            (_) => false,
          );
        }
      });
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

  Future<void> _checkBiometricState() async {
    if (kIsWeb) return;
    try {
      final available = await _biometricService.isBiometricAvailable();
      final enabled = await _biometricService.isBiometricEnabled();
      if (mounted) {
        setState(() {
          _biometricAvailable = available;
          _biometricEnabled = enabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _attemptBiometricAuth() async {
    if (!_biometricAvailable || !_biometricEnabled || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final success = await _biometricService.authenticate();
      if (success && mounted) {
        final storedPin = await ref.read(platformServiceProvider).secureRead('vault_pin');
        if (storedPin != null) {
          _pinController.text = storedPin;
          await _authenticate();
        } else if (mounted) {
          setState(() => _error = 'No stored PIN found');
          setState(() => _isLoading = false);
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticate() async {
    final pin = _pinController.text;
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your PIN');
      return;
    }

    final localContext = context;
    final navigator = Navigator.of(context);
    setState(() => _isLoading = true);
    () async {
      try {
        await _crypto.initialize(pin);
        if (!kIsWeb) {
          await ref.read(platformServiceProvider).secureWrite('vault_pin', pin);
          await ref.read(platformServiceProvider).secureWrite('wrong_attempts', '0');
        }

        final duressService = ref.read(duressServiceProvider);
        final isFakePin = await duressService.isFakePin(pin);

        if (isFakePin) {
          _pinController.clear();
          if (mounted) {
            setState(() {
              _error = null;
              _wrongAttempts = 0;
            });
          }
          navigator.pushReplacementNamed('/admin-panel');
          return;
        }

        if (localContext.mounted && mounted) {
          setState(() {
            _error = null;
            _wrongAttempts = 0;
          });

          PanicMode().init(localContext, ref);
          AutoLock().init(localContext, ref);

          navigator.pushReplacementNamed('/vault-home');
        }
      } catch (e) {
        if (!kIsWeb) {
          try {
            final stored = await ref.read(platformServiceProvider).secureRead('wrong_attempts');
            final currentCount = (int.tryParse(stored ?? '') ?? 0) + 1;
            int counted = currentCount;
            if (counted >= 3) {
              _intruderService.captureIntruder(_crypto);
              counted = 0;
            }
            await ref.read(platformServiceProvider).secureWrite('wrong_attempts', counted.toString());
            if (mounted) setState(() => _wrongAttempts = counted);
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

  @override
  void dispose() {
    ref.read(shakeWipeServiceProvider).stopListening();
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
        title: const Text(
          'Vault Access',
          style: TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Enter Vault PIN',
              style: TextStyle(
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
            if (!kIsWeb && _biometricAvailable && _biometricEnabled)
              IconButton(
                onPressed: _isLoading ? null : _attemptBiometricAuth,
                icon: const Icon(Icons.fingerprint, color: Color(0xFF7F77DD), size: 36),
                tooltip: 'Use Biometrics',
              ),
            if (!kIsWeb && _biometricAvailable && _biometricEnabled)
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
                  : const Text(
                      'Unlock',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
            if (_wrongAttempts >= 3) ...[
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
