// lib/vault/screens/pin_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:local_auth/local_auth.dart';
import '../crypto/vault_crypto.dart';
import '../../core/services/platform_service.dart';
import '../services/file_vault_service.dart';
import '../security/panic_mode.dart';
import '../security/auto_lock.dart';
import '../security/breakin_log.dart';
import 'enter_recovery_screen.dart';

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final TextEditingController _pinController = TextEditingController();
  late final VaultCrypto _crypto;
  final LocalAuthentication _localAuth = LocalAuthentication();
  String? _error;
  bool _isLoading = false;
  bool _biometricAvailable = false;
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    _crypto = ref.read(vaultCryptoProvider);
    _checkBiometricAvailability();
    _loadWrongAttempts();
  }

  Future<void> _loadWrongAttempts() async {
    if (kIsWeb) return;
    try {
      final stored = await ref.read(platformServiceProvider).secureRead('wrong_attempts');
      final count = int.tryParse(stored ?? '') ?? 0;
      if (mounted) {
        setState(() {
          _failedAttempts = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkBiometricAvailability() async {
    if (kIsWeb) return;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (canCheck && isDeviceSupported && mounted) {
        setState(() => _biometricAvailable = true);
      }
    } catch (e) {
      // Biometrics not available
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (kIsWeb) return;
    setState(() => _isLoading = true);
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (authenticated && mounted) {
        final storedPin = await ref.read(platformServiceProvider).secureRead('vault_pin');
        if (storedPin != null) {
          _pinController.text = storedPin;
          _authenticate();
        } else if (mounted) {
          setState(() => _error = 'No stored PIN found');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Biometric authentication failed');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _authenticate() {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
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
        if (localContext.mounted && mounted) {
          setState(() {
            _error = null;
            _failedAttempts = 0;
          });
          
          // Initialize PanicMode shake detector and AutoLock inactivity timer
          PanicMode().init(localContext, ref);
          AutoLock().init(localContext, ref);

          navigator.pushReplacementNamed('/vault-home');
        }
      } catch (e) {
        if (!kIsWeb) {
          try {
            final stored = await ref.read(platformServiceProvider).secureRead('wrong_attempts');
            final currentCount = (int.tryParse(stored ?? '') ?? 0) + 1;
            await ref.read(platformServiceProvider).secureWrite('wrong_attempts', currentCount.toString());
            await BreakInLogService.recordAttempt(currentCount, _crypto);
            if (mounted) {
              setState(() {
                _failedAttempts = currentCount;
              });
            }
          } catch (ex) {
            debugPrint('Failed to save wrong attempts log: $ex');
            if (mounted) {
              setState(() {
                _failedAttempts++;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _failedAttempts++;
            });
          }
        }
        if (mounted) {
          setState(() => _error = 'Invalid PIN');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }();
  }

  Future<void> _takeIntruderSelfie() async {
    if (kIsWeb) return;
    setState(() => _isLoading = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      final image = await controller.takePicture();
      final bytes = await image.readAsBytes();

      final fileVault = ref.read(fileVaultServiceProvider);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await fileVault.saveFile('intruder_selfie_$timestamp.jpg', bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Intruder selfie captured!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to capture selfie');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
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
            if (!kIsWeb && _biometricAvailable)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _authenticateWithBiometrics,
                icon: const Icon(Icons.fingerprint, color: Colors.white),
                label: const Text('Use Biometrics'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F77DD),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (!kIsWeb && _biometricAvailable)
              const SizedBox(height: 12),
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
            if (_failedAttempts >= 3) ...[
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
            if (!kIsWeb) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _takeIntruderSelfie,
                icon: const Icon(Icons.camera_alt, color: Color(0xFF7F77DD)),
                label: const Text(
                  'Take Intruder Selfie',
                  style: TextStyle(color: Color(0xFF7F77DD)),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: Color(0x337F77DD)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
