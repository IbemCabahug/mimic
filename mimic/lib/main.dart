import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/game/game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
