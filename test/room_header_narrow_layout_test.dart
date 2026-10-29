import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
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

  Future<List<String>> pumpAtWidth(WidgetTester tester, double width) async {
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

    // Logical width via physicalSize / DPR (mobile chrome path under 900).
    tester.view.physicalSize = Size(width, 844);
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
    state.setTab(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    final ctx = tester.element(find.byType(RoomCustomizerScreen));
    expect(AppLayout.isDesktop(ctx), isFalse);

    final title = find.byKey(const ValueKey('room_header_title'));
    final dims = find.byKey(const ValueKey('room_header_dims'));
    expect(title, findsOneWidget);
    expect(dims, findsOneWidget);

    final titleBox = tester.renderObject<RenderBox>(title);
    final dimsBox = tester.renderObject<RenderBox>(dims);
    // One-line title/dims: not a tall vertical-glyph column.
    expect(titleBox.size.height, lessThan(28),
        reason: 'title should stay one line at ${width}dp (h=${titleBox.size.height})');
    expect(dimsBox.size.height, lessThan(28),
        reason: 'dims should stay one line at ${width}dp (h=${dimsBox.size.height})');
    expect(titleBox.size.width, greaterThan(120),
        reason: 'title must get horizontal room, not a crushed column');

    expect(find.text('ROOM CUSTOMIZER'), findsOneWidget);
    expect(find.byKey(const ValueKey('room_add_item_btn')), findsOneWidget);
    expect(find.text('Tools'), findsWidgets);
    expect(find.byKey(const ValueKey('room_auto_room_btn')), findsNothing);

    return overflows;
  }

  testWidgets('Room header at 360dp: no overflow, title/dims one line', (tester) async {
    final overflows = await pumpAtWidth(tester, 360);
    expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
  });

  testWidgets('Room header at 412dp: no overflow, title/dims one line', (tester) async {
    final overflows = await pumpAtWidth(tester, 412);
    expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
  });
}
