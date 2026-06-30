// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:room_rig/main.dart';
import 'package:room_rig/models/app_state.dart';

void main() {
  testWidgets('Smoke test room rig app', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const RoomRigApp(),
      ),
    );

    // Verify that the Hub page elements are found
    expect(find.text('Hub'), findsWidgets);
  });
}
