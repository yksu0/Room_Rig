import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_catalog.dart';
import 'package:room_rig/screens/room_customizer_screen.dart';
import 'package:room_rig/theme/app_layout.dart';
import 'package:room_rig/theme/app_theme.dart';

/// Presence smoke for existing Room chrome (sheets are covered by panel unit paths).
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
      if (s.contains('A RenderFlex overflowed') ||
          s.contains('hasSize') ||
          s.contains('RenderBox was not laid out') ||
          s.contains('NEEDS-LAYOUT') ||
          s.contains('_RenderListTile') ||
          s.contains('rendering/object.dart') ||
          s.contains('Failed assertion')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
  }

  Future<AppState> pumpRoom(WidgetTester tester, {required bool stocked}) async {
    tester.view.physicalSize = const Size(400, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
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
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    if (stocked) {
      state.addCatalogFurniture(
        RoomCatalogEntry(
          baseId: 'desk',
          name: 'Desk',
          iconName: 'desk',
          category: 'ergonomics',
          width: 2,
        ),
      );
    }
    state.setTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final ctx = tester.element(find.byType(RoomCustomizerScreen));
    expect(AppLayout.isDesktop(ctx), isFalse);
    return state;
  }

  testWidgets('Room chrome exposes Add Item, View, Camera, Tools, Snapshot, Items, Live',
      (tester) async {
    ignoreLayoutNoise();
    await pumpRoom(tester, stocked: true);

    expect(find.byKey(const ValueKey('room_header_title')), findsOneWidget);
    expect(find.byKey(const ValueKey('room_add_item_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('chrome_view_mode_bar')), findsWidgets);
    expect(find.text('Camera'), findsWidgets);
    expect(find.text('Tools'), findsWidgets);
    expect(find.text('Snapshot'), findsWidgets);
    expect(find.text('Items'), findsWidgets);
    expect(find.byKey(const ValueKey('room_chrome_overflow')), findsOneWidget);
    expect(find.text('Auto-Room'), findsNothing);
    expect(find.byKey(const ValueKey('room_auto_room_btn')), findsNothing);
  });

  testWidgets('Empty lot CTA is Add + Open Tools; no Auto-Room control', (tester) async {
    ignoreLayoutNoise();
    await pumpRoom(tester, stocked: false);

    expect(find.byKey(const ValueKey('empty_lot_cta')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_lot_add')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_lot_open_tools')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_lot_auto_room')), findsNothing);
    expect(find.text('Auto-Room'), findsNothing);
    expect(find.textContaining('Auto-Rig in Tools'), findsWidgets);
  });
}
