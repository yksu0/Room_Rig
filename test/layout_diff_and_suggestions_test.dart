import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/layout_snap_guides.dart';
import 'package:room_rig/widgets/bench_panel_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('summarizeLayoutDiff reports moved furniture', () {
    final before = [
      FurnitureItem(
        id: 'fan',
        name: 'Fan',
        iconName: 'fan',
        category: 'airflow',
        gridX: 1,
        gridY: 1,
      ),
    ];
    final after = [
      FurnitureItem(
        id: 'fan',
        name: 'Fan',
        iconName: 'fan',
        category: 'airflow',
        gridX: 3,
        gridY: 2,
      ),
    ];
    expect(summarizeLayoutDiff(before, after), contains('moved'));
    expect(summarizeLayoutDiff(before, before), 'layout unchanged');
  });

  test('summarizeWhyWins joins top reasons', () {
    expect(summarizeWhyWins(const []), '');
    expect(
      summarizeWhyWins(const ['Opened AC path', 'Moved desk off wall', 'Extra note']),
      'Opened AC path · Moved desk off wall',
    );
  });

  test('LayoutSnapGuides soft-snaps to neighbour edge', () {
    final moving = FurnitureItem(
      id: 'lamp',
      name: 'Lamp',
      iconName: 'lamp',
      category: 'lighting',
      gridX: 2.1,
      gridY: 1,
      width: 1,
      height: 1,
    );
    final other = FurnitureItem(
      id: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'furniture',
      gridX: 4,
      gridY: 1,
      width: 2,
      height: 1,
    );
    final snap = LayoutSnapGuides.apply(
      moving: moving,
      proposedX: 3.85,
      proposedY: 1.05,
      others: [moving, other],
      gridCols: 10,
      gridRows: 10,
    );
    expect(snap.gridX, closeTo(4.0, 0.001));
    expect(snap.guides.any((g) => g.axis == SnapGuideAxis.vertical), isTrue);
  });

  test('suggestedUpgrade points at the weakest category', () {
    final state = AppState();
    state.refreshSimulatedScores();
    final tip = state.suggestedUpgrade();
    expect(tip, isNotNull);
    expect(tip!.name, isNotEmpty);
    expect(tip.index, greaterThanOrEqualTo(0));
  });

  test('buildShareJson includes committed furniture', () {
    final state = AppState();
    final json = state.buildShareJson();
    expect(json, contains('"app": "Room Rig"'));
    expect(json, contains('"furniture"'));
  });
}
