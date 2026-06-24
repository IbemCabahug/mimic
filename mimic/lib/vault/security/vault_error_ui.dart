import 'package:flutter/material.dart';

const String kSecureKeyLostMessage =
  "Can't open this item. The secure key for this device is missing, so vault data can't be decrypted here. "
  "Restore from your recovery phrase or import a previous backup.";

void showSecureKeyLostSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(kSecureKeyLostMessage),
      duration: Duration(seconds: 6),
    ),
  );
}
