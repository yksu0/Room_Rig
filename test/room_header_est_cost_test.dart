import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/price_sources.dart';
import 'package:room_rig/screens/room_customizer_screen.dart';
import 'package:room_rig/theme/app_money.dart';
import 'package:room_rig/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  void ignoreLayoutNoise() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final s = details.toString();
      if (s.contains('A RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
  }

  test('guestRoomLimit is 1 and blocks a second room for guests', () {
    expect(AppState.guestRoomLimit, 1);
    final guest = AppState();
    expect(guest.isSignedIn, isFalse);
    expect(guest.canCreateAnotherRoom, isTrue);

    guest.createManualRoom(
      name: 'Studio',
      lengthMeters: 3.6,
      widthMeters: 4.8,
    );
    expect(guest.savedRooms.length, greaterThanOrEqualTo(1));
    expect(guest.canCreateAnotherRoom, isFalse);

    final signedIn = AppState();
    signedIn.debugSetSignedInForTests(true, userId: 'u-test');
    expect(signedIn.canCreateAnotherRoom, isTrue);
    signedIn.createManualRoom(
      name: 'A',
      lengthMeters: 3.6,
      widthMeters: 4.8,
    );
    expect(signedIn.canCreateAnotherRoom, isTrue);
  });

  for (final width in const [360.0, 390.0, 412.0]) {
    testWidgets(
        'Room header shows est. totalSpent at ${width.toInt()}dp',
        (tester) async {
      ignoreLayoutNoise();
      final overflows = <String>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final s = details.toString();
        if (s.contains('A RenderFlex overflowed')) {
          overflows.add(s);
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = AppState();
      state.createManualRoom(
        name: 'Studio',
        lengthMeters: 3.6,
        widthMeters: 4.8,
      );
      final expected = PriceSources.estimateLabel(
        AppMoney.format(state.totalSpent),
      );
      expect(expected.startsWith('est. '), isTrue);
      expect(expected.contains(AppMoney.symbol), isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const RoomCustomizerScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(const ValueKey('room_header_est_cost')), findsOneWidget);
      expect(find.text(expected), findsOneWidget);
      expect(find.byKey(const ValueKey('room_header_dims')), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join('\n'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}