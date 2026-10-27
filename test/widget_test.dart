// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:room_rig/main.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Smoke test room rig app', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider(create: (_) => AppState()),
        ],
        child: const RoomRigApp(),
      ),
    );
    await tester.pump();

    // Nav shows the four tabs in order: Hub · Room · Scan · Benchmark.
    expect(find.text('Hub'), findsWidgets);
    expect(find.text('Room'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Benchmark'), findsWidgets);
    expect(find.text('Upgrades'), findsNothing);
  });
}
