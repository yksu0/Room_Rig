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

BenchLayouts _build(
  BenchMode mode,
  List<FurnitureItem> furniture, {
  List<FurnitureItem>? baselineFurniture,
}) {
  return BenchLayoutBuilder.build(
    mode: mode,
    roomFurniture: furniture,
    baselineFurniture: baselineFurniture,
    gridCols: 6,
    gridRows: 8,
  );
}

AppState _rigWithPreset() {
  final state = AppState()..selectPreset(RoomPreset.gamingSetup);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  test('baseline is the pinned snapshot, not a drifting live Rig pose', () {
    final state = _rigWithPreset();
    state.ensureBenchBaseline(label: 'opened Bench');
    final deskBefore = state.benchBaselineFurniture.firstWhere((f) => f.id == 'desk');

    state.moveFurniture('desk', 4.0, 6.0, respectCollision: false);
    final deskLive = state.furniture.firstWhere((f) => f.id == 'desk');
    expect(deskLive.gridX, isNot(deskBefore.gridX));

    final layouts = _build(
      BenchMode.airflow,
      state.furniture,
      baselineFurniture: state.benchBaselineFurniture,
    );
    final benched = layouts.myRoom.firstWhere((f) => f.id == 'desk');

    expect(benched.gridX, deskBefore.gridX);
    expect(benched.gridY, deskBefore.gridY);
    expect(layouts.fellBackToSample, isFalse);
  });

  test('ensureBenchBaseline pins once; Set from Rig retargets', () {
    final state = _rigWithPreset();
    expect(state.hasBenchBaseline, isFalse);
    state.ensureBenchBaseline(label: 'opened Bench');
    expect(state.hasBenchBaseline, isTrue);
    expect(state.benchBaselineLabel, 'opened Bench');
    final firstFp = BenchLayoutBuilder.fingerprintOf(state.benchBaselineFurniture);

    state.ensureBenchBaseline(label: 'opened Bench again');
    expect(
      BenchLayoutBuilder.fingerprintOf(state.benchBaselineFurniture),
      firstFp,
      reason: 'ensure must not overwrite an existing pin',
    );

    state.moveFurniture('desk', 4.0, 6.0, respectCollision: false);
    state.setBenchBaselineFromRig(label: 'from Rig');
    expect(state.benchBaselineLabel, 'from Rig');
    expect(
      BenchLayoutBuilder.fingerprintOf(state.benchBaselineFurniture),
      isNot(firstFp),
    );
  });

  test('Auto-Rig inventory matches baseline item ids', () {
    final state = _rigWithPreset();
    state.ensureBenchBaseline();
    state.moveFurniture('ac', 5.0, 7.0, respectCollision: false);

    final layouts = _build(
      BenchMode.airflow,
      state.furniture,
      baselineFurniture: state.benchBaselineFurniture,
    );
    final baseIds = layouts.myRoom.map((f) => f.id).toSet();
    final improvedIds = layouts.improved.map((f) => f.id).toSet();

    expect(improvedIds, baseIds, reason: 'Auto-Rig keeps baseline inventory');
    expect(layouts.improvedReasons, isNotEmpty);
  });

  test('adding furniture after pin does not change Baseline until retarget', () {
    final state = _rigWithPreset();
    state.ensureBenchBaseline();
    final before = _build(
      BenchMode.airflow,
      state.furniture,
      baselineFurniture: state.benchBaselineFurniture,
    );

    final id = state.addCatalogFurniture(
      RigCatalog.items.firstWhere((e) => e.baseId == 'fan'),
    );
    expect(id, isNotNull);

    final after = _build(
      BenchMode.airflow,
      state.furniture,
      baselineFurniture: state.benchBaselineFurniture,
    );
    expect(after.myRoom.length, before.myRoom.length);
    expect(after.myRoom.any((f) => f.id == id), isFalse);
    expect(after.fingerprint, before.fingerprint);

    state.setBenchBaselineFromRig(label: 'from Rig');
    final retargeted = _build(
      BenchMode.airflow,
      state.furniture,
      baselineFurniture: state.benchBaselineFurniture,
    );
    expect(retargeted.myRoom.any((f) => f.id == id), isTrue);
  });

  test('hidden items are left out of the simulated layout', () {
    final state = _rigWithPreset();
    final visible = _build(BenchMode.airflow, state.furniture).myRoom.length;

    state.toggleFurnitureHidden('shelf');
    final after = _build(BenchMode.airflow, state.furniture);

    expect(after.myRoom.length, visible - 1);
    expect(after.myRoom.any((f) => f.id == 'shelf'), isFalse);
  });

  test('the field genuinely changes when furniture moves', () {
    final state = _rigWithPreset();

    AirflowSimSnapshot sim() => AirflowSimulator.build(
          furniture: _build(BenchMode.airflow, state.furniture).myRoom,
          optimized: false,
          particleCount: 0,
          ambientCount: 0,
        );

    final before = sim();
    state.moveFurniture('ac', 5.0, 4.0, respectCollision: false);
    state.moveFurniture('shelf', 1.0, 1.0, respectCollision: false);
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

  test('improved arrangement is identical across every Bench mode', () {
    final state = _rigWithPreset();
    state.moveFurniture('ac', 5.0, 7.5, respectCollision: false);
    state.moveFurniture('shelf', 2.0, 0.5, respectCollision: false);
    state.ensureBenchBaseline();

    String? shared;
    for (final mode in BenchMode.values) {
      final layouts = _build(
        mode,
        state.furniture,
        baselineFurniture: state.benchBaselineFurniture,
      );
      final fp = BenchLayoutBuilder.fingerprintOf(layouts.improved);
      shared ??= fp;
      expect(fp, shared, reason: '${mode.name} Auto-Rig must match other modes');
      expect(
        BenchLayoutBuilder.fingerprintOf(layouts.sample),
        BenchLayoutBuilder.fingerprintOf(
          BenchLayoutBuilder.sampleFor(BenchMode.airflow),
        ),
        reason: '${mode.name} Sample must be the shared reference room',
      );
    }
  });

  test('improved scores at least as well as the room it came from', () {
    final state = _rigWithPreset();
    state.moveFurniture('ac', 5.0, 7.5, respectCollision: false);
    state.moveFurniture('shelf', 2.0, 0.5, respectCollision: false);
    state.moveFurniture('desk', 3.0, 6.0, respectCollision: false);
    state.ensureBenchBaseline();

    final beforeScores = <double>[];
    final afterScores = <double>[];
    for (final mode in BenchMode.values) {
      final layouts = _build(
        mode,
        state.furniture,
        baselineFurniture: state.benchBaselineFurniture,
      );
      beforeScores.add(_score(mode, layouts.myRoom));
      afterScores.add(_score(mode, layouts.improved));
    }
    final beforeMean = beforeScores.reduce((a, b) => a + b) / beforeScores.length;
    final afterMean = afterScores.reduce((a, b) => a + b) / afterScores.length;
    expect(
      afterMean,
      greaterThanOrEqualTo(beforeMean - 1.0),
      reason:
          'shared Auto-Rig mean $afterMean must not tank vs Baseline mean $beforeMean '
          '(per-mode before=$beforeScores after=$afterScores)',
    );
  });

  test('an empty Rig falls back to the reference room and says so', () {
    final layouts = _build(BenchMode.lighting, const []);
    expect(layouts.fellBackToSample, isTrue);
    expect(layouts.myRoom, isNotEmpty);
    expect(layouts.improved, isNotEmpty);
  });

  test('new room clears bench baseline', () {
    final state = _rigWithPreset();
    state.ensureBenchBaseline();
    expect(state.hasBenchBaseline, isTrue);
    state.createManualRoom(name: 'Fresh', lengthMeters: 3.6, widthMeters: 4.8);
    expect(state.hasBenchBaseline, isFalse);
  });

  test('building layouts never mutates the room it was handed', () {
    final state = _rigWithPreset();
    final before = BenchLayoutBuilder.fingerprintOf(state.furniture);

    for (final mode in BenchMode.values) {
      final layouts = _build(mode, state.furniture);
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
