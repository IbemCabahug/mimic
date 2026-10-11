// test/game/screens/pack_select_pro_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/screens/pack_select_screen.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/widgets/paywall_sheet.dart';

void main() {
  testWidgets('PackSelectScreen renders Philippine Folklore as free pack without PRO badge',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isProProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: PackSelectScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Philippine Folklore pack is in the list
    expect(find.text('PHILIPPINE FOLKLORE'), findsOneWidget);
    // Verify no lock icon is shown (folklore is free)
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('Tapping Folklore pack as free user toggles pack without paywall',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isProProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: PackSelectScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap on Philippine Folklore pack
    await tester.tap(find.text('PHILIPPINE FOLKLORE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify PaywallSheet does NOT appear
    expect(find.byType(PaywallSheet), findsNothing);
  });
}
