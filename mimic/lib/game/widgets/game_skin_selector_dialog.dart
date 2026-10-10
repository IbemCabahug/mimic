// lib/game/widgets/game_skin_selector_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/services/game_skin_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/widgets/paywall_sheet.dart';

Future<void> showGameSkinDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const GameSkinSelectorDialog(),
  );
}

class GameSkinSelectorDialog extends ConsumerWidget {
  const GameSkinSelectorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSkin = ref.watch(gameSkinProvider);
    final isPro = ref.watch(isProProvider).value ?? false;

    return AlertDialog(
      backgroundColor: HorrorColors.deepSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
      ),
      title: Text(
        'ATMOSPHERIC SKINS',
        style: GoogleFonts.creepster(
          color: HorrorColors.crimson,
          fontSize: 24,
          letterSpacing: 1.5,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: GameSkinPresets.all.map((skin) {
              final isSelected = skin.id == currentSkin.id;
              final isLocked = skin.isProOnly && !isPro;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    if (isLocked) {
                      Navigator.of(context).pop();
                      showPaywallSheet(context);
                      return;
                    }
                    await ref
                        .read(gameSkinProvider.notifier)
                        .setSkin(skin, isPro: isPro);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? skin.primaryAccent.withValues(alpha: 0.15)
                          : HorrorColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? skin.primaryAccent
                            : (isLocked
                                ? HorrorColors.ashGray.withValues(alpha: 0.4)
                                : HorrorColors.darkRedTint),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Color palette preview swatch
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: skin.scaffoldBackground,
                            border: Border.all(
                              color: skin.primaryAccent,
                              width: 2.0,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: skin.secondaryAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Label & details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    skin.name.toUpperCase(),
                                    style: GoogleFonts.creepster(
                                      fontSize: 18,
                                      color: isSelected
                                          ? skin.primaryAccent
                                          : HorrorColors.fogWhite,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  if (skin.isProOnly) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD97706)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: const Color(0xFFF59E0B),
                                            width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isLocked) ...[
                                            const Icon(Icons.lock_outline,
                                                size: 10,
                                                color: Color(0xFFFBBF24)),
                                            const SizedBox(width: 3),
                                          ],
                                          Text(
                                            'PRO',
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFFFBBF24),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                skin.description,
                                style: GoogleFonts.inter(
                                  color: HorrorColors.ashGray,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: skin.primaryAccent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'CLOSE',
            style: GoogleFonts.creepster(
              color: HorrorColors.ashGray,
              fontSize: 18,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
