import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/room_status_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  testWidgets('RoomStatusStrip honesty chip + scores at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState();
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: RoomStatusStrip(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('room_status_strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('room_status_honesty_chip')), findsOneWidget);
    expect(find.textContaining('Air '), findsOneWidget);
    expect(find.textContaining('ROUGH EST'), findsOneWidget);
  });
}