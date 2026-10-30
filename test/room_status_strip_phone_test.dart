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

  testWidgets('RoomStatusStrip honesty chip + scores at 360 and 412dp', (tester) async {
    for (final width in const [360.0, 412.0]) {
      final state = AppState();
      state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);

      await tester.binding.setSurfaceSize(Size(width, 740));
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

      expect(find.byKey(const ValueKey('room_status_strip')), findsOneWidget,
          reason: 'strip at ${width}dp');
      expect(find.byKey(const ValueKey('room_status_honesty_chip')), findsOneWidget,
          reason: 'chip at ${width}dp');
      expect(find.textContaining('Air '), findsOneWidget, reason: 'Air at ${width}dp');
      expect(find.textContaining('ROUGH EST'), findsOneWidget, reason: 'ROUGH at ${width}dp');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
