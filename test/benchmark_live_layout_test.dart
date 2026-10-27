import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/benchmark_compare_source.dart';
import 'package:room_rig/models/room_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_simulator.dart';
import 'package:room_rig/services/benchmark_layouts.dart';

BenchmarkLayouts _build(
  BenchmarkMode mode,
  List<FurnitureItem> furniture, {
  List<FurnitureItem>? leftFurniture,
  List<FurnitureItem>? rightFurniture,
  bool rightIsAutoRig = true,
}) {
  return BenchmarkLayoutBuilder.build(
    mode: mode,
    roomFurniture: furniture,
    leftFurniture: leftFurniture,
    rightFurniture: rightFurniture,
    rightIsAutoRig: rightIsAutoRig,
    autoRigSeed: leftFurniture ?? furniture,
    gridCols: 6,
    gridRows: 8,
  );
}

AppState _roomWithPreset() {
  return AppState()..selectPreset(RoomPreset.gamingSetup);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  test('default compare is Current Room vs Auto-Rig', () {
    final state = _roomWithPreset();
    expect(state.benchmarkCompareLeft.isCurrentRoom, isTrue);
    expect(state.benchmarkCompareRight.isAutoRig, isTrue);
  });

  test('snapshot checkpoint can be selected as Left', () {
    final state = _roomWithPreset();
    expect(state.checkpointActiveRoom('Before move'), isTrue);
    final id = state.activeRoomRevisions.last.id;
    state.moveFurniture('desk', 4.0, 6.0, respectCollision: false);
    state.setBenchmarkCompareLeft(BenchmarkCompareSource.checkpoint(id));

    final left = state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft)!;
    final liveDesk = state.furniture.firstWhere((f) => f.id == 'desk');
    final snapDesk = left.firstWhere((f) => f.id == 'desk');
    expect(snapDesk.gridX, isNot(liveDesk.gridX));
  });

  test('Auto-Rig inventory matches left seed ids', () {
    final state = _roomWithPreset();
    state.moveFurniture('ac', 5.0, 7.0, respectCollision: false);
    final left =
        state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft) ?? const [];
    final layouts = _build(
      BenchmarkMode.airflow,
      state.furniture,
      leftFurniture: left,
      rightIsAutoRig: true,
    );
    expect(
      layouts.improved.map((f) => f.id).toSet(),
      left.map((f) => f.id).toSet(),
    );
    expect(layouts.rightIsAutoRig, isTrue);
  });

  test('checkpoint vs checkpoint does not run Auto-Rig', () {
    final state = _roomWithPreset();
    state.checkpointActiveRoom('A');
    final a = state.activeRoomRevisions.last.id;
    state.moveFurniture('desk', 3.0, 5.0, respectCollision: false);
    state.checkpointActiveRoom('B');
    final b = state.activeRoomRevisions.last.id;

    final left = state.resolveBenchmarkCompareFurniture(
      BenchmarkCompareSource.checkpoint(a),
    )!;
    final right = state.resolveBenchmarkCompareFurniture(
      BenchmarkCompareSource.checkpoint(b),
    )!;
    final layouts = _build(
      BenchmarkMode.airflow,
      state.furniture,
      leftFurniture: left,
      rightFurniture: right,
      rightIsAutoRig: false,
    );
    expect(layouts.rightIsAutoRig, isFalse);
    expect(layouts.improvedReasons, isEmpty);
    expect(
      BenchmarkLayoutBuilder.fingerprintOf(layouts.improved),
      BenchmarkLayoutBuilder.fingerprintOf(right),
    );
  });

  test('adding furniture after pin does not change checkpoint Left', () {
    final state = _roomWithPreset();
    state.checkpointActiveRoom('Pinned');
    final id = state.activeRoomRevisions.last.id;
    state.setBenchmarkCompareLeft(BenchmarkCompareSource.checkpoint(id));
    final before = state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft)!;

    final added = state.addCatalogFurniture(
      RoomCatalog.items.firstWhere((e) => e.baseId == 'fan'),
    );
    expect(added, isNotNull);
    final after = state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft)!;
    expect(after.length, before.length);
    expect(after.any((f) => f.id == added), isFalse);
  });

  test('hidden items are left out of the simulated layout', () {
    final state = _roomWithPreset();
    final visible = _build(BenchmarkMode.airflow, state.furniture).myRoom.length;

    state.toggleFurnitureHidden('shelf');
    final after = _build(BenchmarkMode.airflow, state.furniture);

    expect(after.myRoom.length, visible - 1);
    expect(after.myRoom.any((f) => f.id == 'shelf'), isFalse);
  });

  test('the field genuinely changes when furniture moves', () {
    final state = _roomWithPreset();

    AirflowSimSnapshot sim() => AirflowSimulator.build(
          furniture: _build(BenchmarkMode.airflow, state.furniture).myRoom,
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

  test('improved arrangement is identical across every Benchmark mode', () {
    final state = _roomWithPreset();
    state.moveFurniture('ac', 5.0, 7.5, respectCollision: false);
    state.moveFurniture('shelf', 2.0, 0.5, respectCollision: false);
    final left =
        state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft) ?? const [];

    String? shared;
    for (final mode in BenchmarkMode.values) {
      final layouts = _build(mode, state.furniture, leftFurniture: left);
      final fp = BenchmarkLayoutBuilder.fingerprintOf(layouts.improved);
      shared ??= fp;
      expect(fp, shared, reason: '${mode.name} Auto-Rig must match other modes');
    }
  });

  test('new room resets compare sources', () {
    final state = _roomWithPreset();
    state.checkpointActiveRoom('X');
    state.setBenchmarkCompareLeft(
      BenchmarkCompareSource.checkpoint(state.activeRoomRevisions.last.id),
    );
    state.createManualRoom(name: 'Fresh', lengthMeters: 3.6, widthMeters: 4.8);
    expect(state.benchmarkCompareLeft.isCurrentRoom, isTrue);
    expect(state.benchmarkCompareRight.isAutoRig, isTrue);
  });

  test('building layouts never mutates the room it was handed', () {
    final state = _roomWithPreset();
    final before = BenchmarkLayoutBuilder.fingerprintOf(state.furniture);

    for (final mode in BenchmarkMode.values) {
      final layouts = _build(mode, state.furniture);
      layouts.myRoom.first.copyWith(gridX: 99);
      expect(
        BenchmarkLayoutBuilder.fingerprintOf(state.furniture),
        before,
        reason: '${mode.name} changed the Room just by being looked at',
      );
    }
  });

  test('checkpointActiveRoom smoke for Snapshot chrome', () {
    final state = _roomWithPreset();
    expect(state.activeRoomRevisions, isEmpty);
    expect(state.checkpointActiveRoom('Snapshot 08:00'), isTrue);
    expect(state.activeRoomRevisions.length, 1);
    expect(state.activeRoomRevisions.first.label, 'Snapshot 08:00');
  });
}

