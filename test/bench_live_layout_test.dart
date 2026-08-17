import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:room_rig/services/airflow_simulator.dart';
import 'package:room_rig/services/bench_layouts.dart';
import 'package:room_rig/services/ergonomics_optimizer.dart';
import 'package:room_rig/services/lighting_optimizer.dart';
import 'package:room_rig/services/spatial_analyzer.dart';

BenchLayouts _build(BenchMode mode, List<FurnitureItem> furniture) {
  return BenchLayoutBuilder.build(
    mode: mode,
    roomFurniture: furniture,
    gridCols: 6,
    gridRows: 8,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  test('my room is the live Rig furniture, not the demo layout', () {
    final state = AppState();
    state.moveFurniture('desk', 4.0, 6.0);
    final desk = state.furniture.firstWhere((f) => f.id == 'desk');

    final layouts = _build(BenchMode.airflow, state.furniture);
    final benched = layouts.myRoom.firstWhere((f) => f.id == 'desk');

    expect(benched.gridX, desk.gridX);
    expect(benched.gridY, desk.gridY);
    expect(layouts.fellBackToSample, isFalse);

    // The sample is still available, and it is a different room.
    expect(layouts.sample.firstWhere((f) => f.id == 'desk').gridX, isNot(desk.gridX));
  });

  test('adding furniture in the Rig shows up in what the Bench simulates', () {
    final state = AppState();
    final before = _build(BenchMode.airflow, state.furniture);

    final id = state.addCatalogFurniture(
      RigCatalog.items.firstWhere((e) => e.baseId == 'fan'),
    );
    expect(id, isNotNull);

    final after = _build(BenchMode.airflow, state.furniture);
    expect(after.myRoom.length, before.myRoom.length + 1);
    expect(after.myRoom.any((f) => f.id == id), isTrue);
    expect(after.fingerprint, isNot(before.fingerprint));
  });

  test('hidden items are left out of the simulated layout', () {
    final state = AppState();
    final visible = _build(BenchMode.airflow, state.furniture).myRoom.length;

    state.toggleFurnitureHidden('shelf');
    final after = _build(BenchMode.airflow, state.furniture);

    expect(after.myRoom.length, visible - 1);
    expect(after.myRoom.any((f) => f.id == 'shelf'), isFalse);
  });

  test('the field genuinely changes when furniture moves', () {
    final state = AppState();

    AirflowSimSnapshot sim() => AirflowSimulator.build(
          furniture: _build(BenchMode.airflow, state.furniture).myRoom,
          optimized: false,
          particleCount: 0,
          ambientCount: 0,
        );

    final before = sim();
    state.moveFurniture('ac', 5.0, 4.0);
    state.moveFurniture('shelf', 1.0, 1.0);
    final after = sim();

    var differing = 0;
    for (int i = 0; i < before.field.speed.length; i++) {
      if ((before.field.speed[i] - after.field.speed[i]).abs() > 0.01) differing++;
    }
    expect(
      differing,
      greaterThan(before.field.speed.length ~/ 50),
      reason: 'moving the AC and a blocker must change the velocity field',
    );
  });

  test('improved is derived from your room, not from the demo layout', () {
    final state = AppState();
    state.moveFurniture('ac', 5.0, 7.0);

    final layouts = _build(BenchMode.airflow, state.furniture);
    final myIds = layouts.myRoom.map((f) => f.id).toSet();
    final improvedIds = layouts.improved.map((f) => f.id).toSet();

    expect(improvedIds, myIds, reason: 'the improved run keeps your inventory');
    expect(layouts.improvedReasons, isNotEmpty);
  });

  test('improved scores at least as well as the room it came from', () {
    for (final mode in BenchMode.values) {
      final state = AppState();
      // A deliberately poor starting point.
      state.moveFurniture('ac', 5.0, 7.5);
      state.moveFurniture('shelf', 2.0, 0.5);
      state.moveFurniture('desk', 3.0, 6.0);

      final layouts = _build(mode, state.furniture);
      final before = _score(mode, layouts.myRoom);
      final after = _score(mode, layouts.improved);

      expect(
        after,
        greaterThanOrEqualTo(before - 0.5),
        reason: '${mode.name}: improved must not be worse than the room it optimized',
      );
    }
  });

  test('an empty Rig falls back to the reference room and says so', () {
    final layouts = _build(BenchMode.lighting, const []);
    expect(layouts.fellBackToSample, isTrue);
    expect(layouts.myRoom, isNotEmpty);
    expect(layouts.improved, isNotEmpty);
  });

  test('every mode reads the same live room', () {
    final state = AppState();
    state.moveFurniture('bed', 0.0, 0.5);
    final bed = state.furniture.firstWhere((f) => f.id == 'bed');

    for (final mode in BenchMode.values) {
      final layouts = _build(mode, state.furniture);
      final benched = layouts.myRoom.firstWhere((f) => f.id == 'bed');
      expect(benched.gridX, bed.gridX, reason: mode.name);
      expect(benched.gridY, bed.gridY, reason: mode.name);
    }
  });

  test('building layouts never mutates the room it was handed', () {
    final state = AppState();
    final before = BenchLayoutBuilder.fingerprintOf(state.furniture);

    for (final mode in BenchMode.values) {
      final layouts = _build(mode, state.furniture);
      // Mutating the returned copies must not reach back into app state.
      layouts.myRoom.first.copyWith(gridX: 99);
      expect(
        BenchLayoutBuilder.fingerprintOf(state.furniture),
        before,
        reason: '${mode.name} changed the Rig just by being looked at',
      );
    }
  });
}

double _score(BenchMode mode, List<FurnitureItem> furniture) {
  switch (mode) {
    case BenchMode.airflow:
      return AirflowOptimizer.evaluate(furniture).circulationScore;
    case BenchMode.lighting:
      return LightingOptimizer.evaluate(furniture).exposureScore;
    case BenchMode.ergonomics:
      return ErgonomicsOptimizer.evaluate(furniture).comfortScore;
    case BenchMode.spatial:
      return SpatialAnalyzer.evaluate(
        furniture: furniture,
        gridCols: 6,
        gridRows: 8,
      ).overallScore;
  }
}
