import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Create marks the room ready; selectPreset alone does not', () {
    final state = AppState();
    expect(state.roomIsReady, isFalse);

    state.selectPreset(RoomPreset.gamingSetup);
    expect(state.roomIsReady, isFalse);
    expect(state.activeRoomLayout?.scanSource, 'preset');

    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    expect(state.roomIsReady, isTrue);
    expect(state.activeRoomLayout?.scanSource, 'manual');
    expect(state.scanComplete, isFalse);
  });

  test('placed upgrades survive applyFurnitureLayout retainV1', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    expect(state.toggleUpgrade(0), isTrue);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isTrue);

    state.applyFurnitureLayout(state.furniture, markOptimized: true);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isTrue);
    expect(state.upgrades.first['added'], isTrue);
    expect(RoomCatalog.isV1Item(state.furniture.firstWhere((f) => f.id == 'upg_fan')), isTrue);
  });

  test('Benchmark Apply Score Delta uses geometry-before not catalog impact tags', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);

    // Dirty the scores with a move so Hub would show ROUGH EST.
    final movable = state.furniture.firstWhere(
      (f) => f.iconName != 'door' && f.iconName != 'window' && f.iconName != 'ac',
    );
    state.moveFurniture(movable.id, movable.gridX + 0.5, movable.gridY);
    expect(state.scoresAreSimulated, isTrue);

    // ROUGH rings are live geometry — same evaluator as Benchmark — not impact tags.
    final simBefore = AirflowOptimizer.evaluate(state.committedFurniture).circulationScore;
    expect(state.airflowScore, closeTo(simBefore, 0.01));

    final before = List<FurnitureItem>.from(state.furniture.map((f) => f.copyWith()));
    state.applyFurnitureLayout(before, markOptimized: true);

    expect(state.scoresAreSimulated, isFalse);
    expect(state.isOptimized, isTrue);
    expect(state.originalScores?['airflow'], closeTo(simBefore, 0.6));
    // Apply of the same poses → modest overall delta (composite vs snapshot).
    final delta = state.overallScore - state.previousOverallScore;
    expect(delta.abs(), lessThan(25), reason: 'sim-to-sim delta should be modest');
  });

  test('Hub base scores ignore Place ghosts', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    final before = state.airflowScore;
    final lamp = RoomCatalog.items.firstWhere((e) => e.baseId == 'lamp');
    state.addCatalogFurniture(lamp, pending: true);
    expect(state.hasPendingPlacement, isTrue);
    // Ghost should not change base estimate while pending.
    expect(state.airflowScore, closeTo(before, 0.01));
  });

  test('dragging or rotating a Place ghost does not clear BENCHMARK OK', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.applyFurnitureLayout(state.furniture, markOptimized: true);
    expect(state.isOptimized, isTrue);
    expect(state.scoresAreSimulated, isFalse);

    final lamp = RoomCatalog.items.firstWhere((e) => e.baseId == 'lamp');
    final id = state.addCatalogFurniture(lamp, pending: true)!;
    state.moveFurniture(id, state.furniture.firstWhere((f) => f.id == id).gridX + 1, 3);
    expect(state.isOptimized, isTrue, reason: 'ghost drag must not clear Applied');
    expect(state.scoresAreSimulated, isFalse);

    state.rotateFurniture(id, deltaDegrees: 90);
    expect(state.isOptimized, isTrue);
    expect(state.hasPendingPlacement, isTrue);
  });

  test('Place ghost is not written into persisted / stashed furniture', () {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    final lamp = RoomCatalog.items.firstWhere((e) => e.baseId == 'lamp');
    final id = state.addCatalogFurniture(lamp, pending: true)!;
    state.rotateFurniture(id, deltaDegrees: 90);

    // Force a stash via a committed-item edit (ghost must stay out of My Rooms).
    final desk = state.furniture.firstWhere((f) => f.id == 'desk');
    state.moveFurniture(desk.id, desk.gridX + 0.5, desk.gridY);

    final room = state.savedRooms.firstWhere((r) => r.id == state.activeRoomId);
    expect(room.furniture.any((f) => f.id == id), isFalse,
        reason: 'My Rooms must not harden unfinished Place ghosts');
    expect(state.hasPendingPlacement, isTrue);
    expect(state.furniture.any((f) => f.id == id), isTrue);
  });
}
