import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricResult { success, failed, unavailable, notEnrolled, lockedOut, error }

class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<BiometricResult> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NotAvailable':
          return BiometricResult.unavailable;
        case 'NotEnrolled':
          return BiometricResult.notEnrolled;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          return BiometricResult.lockedOut;
        default:
          return BiometricResult.error;
      }
    }
  }
}
