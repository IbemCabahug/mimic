import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() async {
  final file = File('debug_export.mimic');
  if (!await file.exists()) {
    print('File not found');
    return;
  }
  final bytes = await file.readAsBytes();
  
  if (bytes.length < 45) {
    print('File too short');
    return;
  }
  
  final magic = bytes.sublist(0, 4);
  final magicStr = utf8.decode(magic, allowMalformed: true);
  final magicValid = magic[0] == 0x4D && magic[1] == 0x4D && magic[2] == 0x49 && magic[3] == 0x43;
  print('Magic Header: $magicStr (Valid: $magicValid)');
  
  final version = bytes[4];
  print('Version: $version (Valid: ${version == 0x01})');
  
  final storedChecksum = bytes.sublist(5, 37);
  final payloadBytes = bytes.sublist(45);
  final computedChecksum = sha256.convert(payloadBytes).bytes;
  
  bool match = true;
  for(int i=0; i<32; i++){
    if(storedChecksum[i] != computedChecksum[i]) match = false;
  }
  print('Checksum Match: $match');
  
  final jsonString = utf8.decode(payloadBytes);
  final Map<String, dynamic> payload = jsonDecode(jsonString);
  
  print('\nPayload Keys:');
  for (final key in payload.keys) {
    final value = payload[key];
    int length = 0;
    if (value is String) length = value.length;
    else if (value is Map) length = value.length;
    else if (value is List) length = value.length;
    else length = value.toString().length;
    print('- $key: length $length');
  }
  
  final hasBlob = payload.containsKey('recovery_blob') && payload['recovery_blob'] != null && payload['recovery_blob'].toString().isNotEmpty;
  final hasSalt = payload.containsKey('recovery_salt') && payload['recovery_salt'] != null && payload['recovery_salt'].toString().isNotEmpty;
  print('\nExplicit Checks:');
  print('recovery_blob present and non-empty: $hasBlob');
  print('recovery_salt present and non-empty: $hasSalt');
}
