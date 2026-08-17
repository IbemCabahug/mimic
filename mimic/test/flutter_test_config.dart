import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointycastle/export.dart';

import 'package:flutter/services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mimic/storage'), (MethodCall methodCall) async {
      if (methodCall.method == 'getAvailableBytes') {
        return 1 << 50;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mimic/keystore'), (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'ensureKey':
          return null;
        case 'wrap':
          final Uint8List original = methodCall.arguments['bytes'] as Uint8List;
          final iv = Uint8List(12); // dummy IV
          final combined = Uint8List(iv.length + original.length);
          combined.setRange(0, iv.length, iv);
          combined.setRange(iv.length, combined.length, original);
          return combined;
        case 'unwrap':
          final Uint8List combined = methodCall.arguments['bytes'] as Uint8List;
          if (combined.length < 12) {
            throw PlatformException(code: 'KEY_INVALID', message: 'Invalid wrapped key length');
          }
          final original = combined.sublist(12);
          return original;
        case 'deleteKey':
          return null;
        case 'pbkdf2':
          final Uint8List password = methodCall.arguments['password'] as Uint8List;
          final Uint8List salt = methodCall.arguments['salt'] as Uint8List;
          final int iterations = methodCall.arguments['iterations'] as int;
          final int keyLength = methodCall.arguments['keyLength'] as int;
          final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
          pbkdf2.init(Pbkdf2Parameters(salt, iterations, keyLength));
          return pbkdf2.process(password);
        case 'elapsedRealtime':
          return 1000000;
        default:
          return null;
      }
    });
  });
  await testMain();
}
