// tool/license_generator.dart
//
// Standalone Dart CLI tool for generating and verifying offline Mimic Pro license keys.
//
// Usage:
//   dart run tool/license_generator.dart
//   dart run tool/license_generator.dart --count 20
//   dart run tool/license_generator.dart --count 100 --csv keys.csv
//   dart run tool/license_generator.dart --verify MIMIC-1A2B-3C4D-5E6F-7A8B
//   dart run tool/license_generator.dart --type tester --count 5
//
// Can specify custom secret:
//   dart run tool/license_generator.dart --secret "my_custom_secret"

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  var count = 1;
  var typeCode = 0x01; // Lifetime Pro
  var typeName = 'Lifetime Pro';
  String? csvPath;
  String? verifyKey;
  String? secret = Platform.environment['MIMIC_LICENSE_SECRET'];

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if ((arg == '--count' || arg == '-c') && i + 1 < args.length) {
      count = int.tryParse(args[++i]) ?? 1;
    } else if ((arg == '--type' || arg == '-t') && i + 1 < args.length) {
      final t = args[++i].toLowerCase();
      if (t == 'tester' || t == 'beta') {
        typeCode = 0x02;
        typeName = 'Beta Tester Access';
      } else {
        typeCode = 0x01;
        typeName = 'Lifetime Pro';
      }
    } else if (arg == '--csv' && i + 1 < args.length) {
      csvPath = args[++i];
    } else if (arg == '--verify' && i + 1 < args.length) {
      verifyKey = args[++i];
    } else if (arg == '--secret' && i + 1 < args.length) {
      secret = args[++i];
    } else if (arg == '--help' || arg == '-h') {
      _printHelp();
      return;
    }
  }

  // Fail closed (LIC-02): the tool must never fall back to a hardcoded
  // default secret — a missing secret is an error, not a fallback.
  if (secret == null || secret.isEmpty) {
    stderr.writeln(
      'ERROR: no license secret configured.\n'
      'Set MIMIC_LICENSE_SECRET in your environment, or pass --secret <value>.\n'
      'The secret is rotated independently — never hardcode it in this tool.',
    );
    exit(1);
  }

  // Verification Mode
  if (verifyKey != null) {
    _verifySingleKey(verifyKey, secret);
    return;
  }

  // Generation Mode
  print('====================================================');
  print('          MIMIC PRO OFFLINE LICENSE GENERATOR       ');
  print('====================================================');
  print('Type:     $typeName (0x${typeCode.toRadixString(16).padLeft(2, '0')})');
  print('Quantity: $count key(s)');
  print('Secret:   ${secret.substring(0, min(10, secret.length))}... (length ${secret.length})');
  print('----------------------------------------------------');

  final keys = <String>[];
  final rng = Random.secure();

  for (var i = 0; i < count; i++) {
    final nonceBytes = [rng.nextInt(256), rng.nextInt(256), rng.nextInt(256)];
    final payload = [typeCode, ...nonceBytes];

    final hmac = Hmac(sha256, utf8.encode(secret));
    final payloadHex = payload.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
    final tag = hmac.convert(utf8.encode(payloadHex)).bytes.sublist(0, 4);

    final allBytes = [...payload, ...tag];
    final hex = allBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final formatted = 'MIMIC-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}';
    keys.add(formatted);
  }

  if (csvPath != null) {
    final file = File(csvPath);
    final buffer = StringBuffer();
    buffer.writeln('LicenseKey,Type,IssuedAt');
    final now = DateTime.now().toUtc().toIso8601String();
    for (final k in keys) {
      buffer.writeln('$k,$typeName,$now');
    }
    file.writeAsStringSync(buffer.toString());
    print('Successfully exported $count key(s) to: $csvPath');
  } else {
    for (var i = 0; i < keys.length; i++) {
      print('[${(i + 1).toString().padLeft(count.toString().length, ' ')}]  ${keys[i]}');
    }
  }

  print('----------------------------------------------------');
  print('Done! Ready to distribute or test in Mimic.');
  print('====================================================\n');
}

void _verifySingleKey(String rawKey, String secret) {
  var clean = rawKey.trim().toUpperCase();
  if (clean.startsWith('MIMIC-')) clean = clean.substring(6);
  if (clean.startsWith('MIMIC')) clean = clean.substring(5);
  clean = clean.replaceAll(RegExp(r'[^0-9A-F]'), '');

  if (clean.length != 16) {
    print('❌ FAILED: Invalid key length (${clean.length} hex chars, expected 16)');
    exitCode = 1;
    return;
  }

  final bytes = <int>[];
  for (var i = 0; i < 16; i += 2) {
    bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }

  final payload = bytes.sublist(0, 4);
  final providedTag = bytes.sublist(4, 8);

  final hmac = Hmac(sha256, utf8.encode(secret));
  final payloadHex = payload.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
  final expectedTag = hmac.convert(utf8.encode(payloadHex)).bytes.sublist(0, 4);

  var diff = 0;
  for (var i = 0; i < 4; i++) {
    diff |= providedTag[i] ^ expectedTag[i];
  }

  if (diff != 0) {
    print('❌ FAILED: Signature mismatch! Key is tampered or generated with a different secret.');
    exitCode = 1;
    return;
  }

  final typeCode = payload[0];
  final typeDesc = typeCode == 0x01
      ? 'Lifetime Pro'
      : (typeCode == 0x02 ? 'Beta Tester Access' : 'Unknown Type (0x$typeCode)');

  final formatted = 'MIMIC-${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}-${clean.substring(12, 16)}';
  print('✅ VALID KEY: $formatted');
  print('Type:        $typeDesc');
  print('Signature:   HMAC-SHA256 verified successfully.');
}

void _printHelp() {
  print('''
Mimic Pro Offline License Key Generator CLI

Options:
  -c, --count <n>       Number of keys to generate (default: 1)
  -t, --type <name>     License type: "lifetime" (default) or "tester"
  --csv <path>          Output generated keys to a CSV file
  --verify <key>        Verify an existing license key
  --secret <secret>     Override default signing secret key
  -h, --help            Show this help documentation

Examples:
  dart run tool/license_generator.dart --count 5
  dart run tool/license_generator.dart --count 50 --csv keys.csv
  dart run tool/license_generator.dart --verify MIMIC-1234-5678-ABCD-EF01
''');
}
