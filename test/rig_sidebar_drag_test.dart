import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/screens/rig_customizer_screen.dart';
import 'package:room_rig/widgets/empty_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  Future<AppState> pumpRig(WidgetTester tester) async {
    final state = AppState();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: RigCustomizerScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return state;
  }

  testWidgets('sidebar opens and lists layout items', (tester) async {
    await pumpRig(tester);

    expect(find.text('Items'), findsOneWidget);
    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

    expect(find.text('ROOM ITEMS'), findsOneWidget);
    expect(find.text('LAYOUT ITEMS'), findsOneWidget);
    expect(find.textContaining('Gaming Desk'), findsWidgets);

    // Scroll drawer list to the empty scan state.
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No scan objects yet'), findsOneWidget);
  });

  testWidgets('2D drag moves furniture with collision snap', (tester) async {
    final state = await pumpRig(tester);
    expect(find.text('RIG CUSTOMIZER'), findsOneWidget);

    final before = state.furniture.firstWhere((f) => f.id == 'lamp');
    final beforeX = before.gridX;
    final beforeY = before.gridY;

    state.beginFurnitureGesture();
    state.moveFurniture('lamp', 0.0, 7.0);
    state.endFurnitureGesture();
    await tester.pump();

    final after = state.furniture.firstWhere((f) => f.id == 'lamp');
    expect(after.gridX != beforeX || after.gridY != beforeY, isTrue);
    expect(state.canUndoLayout, isTrue);

    final desk = state.furniture.firstWhere((f) => f.id == 'desk');
    state.beginFurnitureGesture();
    state.moveFurniture('chair', desk.gridX + 0.5, desk.gridY);
    state.endFurnitureGesture();
    await tester.pump();
    final chair = state.furniture.firstWhere((f) => f.id == 'chair');
    expect(chair.gridX == desk.gridX + 0.5 && chair.gridY == desk.gridY, isFalse);
  });
}
