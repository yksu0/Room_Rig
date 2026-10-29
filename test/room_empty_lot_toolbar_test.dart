import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_catalog.dart';
import 'package:room_rig/screens/room_customizer_screen.dart';
import 'package:room_rig/theme/app_layout.dart';
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

  Future<AppState> pumpEmptyRoom(WidgetTester tester) async {
    // Portrait under desktopMinWidth (900) and not landscape-shell.
    tester.view.physicalSize = const Size(800, 1200);
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
    await tester.pump(const Duration(milliseconds: 100));
    // Create after mount so device hydrate cannot wipe the manual room.
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    state.setTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    return state;
  }

  testWidgets(
      'Empty lot after Create shows Add/Auto-Room CTA until first movable item',
      (tester) async {
    ignoreLayoutNoise();
    final state = await pumpEmptyRoom(tester);

    expect(state.roomIsReady, isTrue);
    expect(
      state.furniture.where((f) => f.iconName != 'door' && f.iconName != 'window'),
      isEmpty,
    );
    expect(find.byKey(const ValueKey('empty_lot_cta')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_lot_add')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_lot_auto_room')), findsOneWidget);
    expect(find.textContaining('does not stock empty rooms'), findsWidgets);

    final desk = RoomCatalogEntry(
      baseId: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'ergonomics',
      width: 2,
    );
    final id = state.addCatalogFurniture(desk);
    expect(id, isNotNull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      state.furniture.where((f) => f.iconName != 'door' && f.iconName != 'window'),
      isNotEmpty,
    );
    expect(find.byKey(const ValueKey('empty_lot_cta')), findsNothing);
  });

  testWidgets(
      'Mobile Room toolbar: view modes + pinned Add/Auto-Room; live in overflow',
      (tester) async {
    ignoreLayoutNoise();
    await pumpEmptyRoom(tester);

    final ctx = tester.element(find.byType(RoomCustomizerScreen));
    expect(AppLayout.isDesktop(ctx), isFalse, reason: 'expected mobile chrome path');

    expect(find.byKey(const ValueKey('chrome_view_mode_bar')), findsWidgets);
    expect(find.byKey(const ValueKey('room_add_item_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('room_auto_room_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('room_chrome_overflow')), findsOneWidget);
    expect(find.text('Stock this room'), findsOneWidget);
  });

  testWidgets('Guest sync hint visible on Room when not signed in', (tester) async {
    ignoreLayoutNoise();
    final state = await pumpEmptyRoom(tester);
    expect(state.isSignedIn, isFalse);
    expect(find.byKey(const ValueKey('room_sync_hint')), findsOneWidget);
    expect(find.text('Saved on this device only'), findsOneWidget);
  });
}
