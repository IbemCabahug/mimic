import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reference-counted controller for the Android FLAG_SECURE window flag.
/// FLAG_SECURE is enabled while one or more vault screens are mounted and
/// disabled once the last one is gone. No-op on web; safely ignores the
/// platform channel being absent (e.g. in tests / non-Android).
class SecureFlagController {
  SecureFlagController._();
  static final SecureFlagController instance = SecureFlagController._();

  static const MethodChannel _channel = MethodChannel('mimic/secure_screen');
  int _count = 0;

  void acquire() {
    _count++;
    if (_count == 1) _setSecure(true);
  }

  void release() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) _setSecure(false);
  }

  void _setSecure(bool on) {
    if (kIsWeb) return;
    // Fire-and-forget; ignore MissingPluginException on non-Android/tests.
    _channel.invokeMethod(on ? 'enable' : 'disable').catchError((_) {});
  }
}

/// Wrap a screen's content in this to enable FLAG_SECURE while it is mounted.
class SecureGuard extends StatefulWidget {
  final Widget child;
  const SecureGuard({super.key, required this.child});

  @override
  State<SecureGuard> createState() => _SecureGuardState();
}

class _SecureGuardState extends State<SecureGuard> {
  @override
  void initState() {
    super.initState();
    SecureFlagController.instance.acquire();
  }

  @override
  void dispose() {
    SecureFlagController.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
