import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/game.dart';

void main() {
  testWidgets('Game home screen loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MimicGame());

    // Verify that the title 'MIMIC' is displayed.
    expect(find.text('MIMIC'), findsOneWidget);

    // Verify that the 'Play' button is displayed.
    expect(find.text('Play'), findsOneWidget);
  });
}
