import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/game/data/language_store.dart';
import 'package:mimic/vault/security/auto_lock.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LanguageStore.load();
  await AutoLock.wipeTransientPlaintext();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.creepster(),
      GoogleFonts.inter(),
    ]);
  } catch (_) {
    // Offline or failed, continue booting
  }
  runApp(const MimicGame());
}
