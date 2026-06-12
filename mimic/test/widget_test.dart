import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/game.dart';

void main() {
  testWidgets('Game home screen loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MimicGame());
    await tester.pump(); // build LoadingScreen
    
    // Verify the 'MIMIC' wordmark is visible on the loading screen
    expect(find.text('MIMIC'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2)); // elapse min display + fire navigation
    await tester.pump(); // process pushReplacement
    await tester.pump(const Duration(milliseconds: 500)); // Process home screen particles

    // Verify that the title 'MIMIC' is displayed.
    expect(find.text('MIMIC'), findsOneWidget);

    // Verify that the 'BEGIN' button is displayed.
    expect(find.text('BEGIN'), findsOneWidget);
  });
}
