import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('upgrade remove dirties scores instead of marking BENCH OK', () {
    final state = AppState();
    state.runOptimization(goal: 'airflow');
    expect(state.scoresAreSimulated, isFalse);
    expect(state.isOptimized, isTrue);

    expect(state.toggleUpgrade(0), isTrue); // add
    expect(state.scoresAreSimulated, isTrue);
    expect(state.isOptimized, isFalse);

    state.runOptimization(goal: 'airflow');
    expect(state.scoresAreSimulated, isFalse);

    expect(state.toggleUpgrade(0), isTrue); // remove
    expect(state.scoresAreSimulated, isTrue);
    expect(state.isOptimized, isFalse);
  });

  test('rig move clears Applied while keeping restore snapshot', () {
    final state = AppState();
    state.runOptimization(goal: 'airflow');
    expect(state.isOptimized, isTrue);
    expect(state.hasCompareSnapshot, isTrue);

    final movable = state.furniture.firstWhere(
      (f) =>
          f.iconName != 'door' &&
          f.iconName != 'window' &&
          !f.locked &&
          state.canMoveFurniture(f),
    );
    // Prefer an unconstrained move so collision snap-back cannot no-op the edit.
    state.moveFurniture(
      movable.id,
      movable.gridX + 1.5,
      movable.gridY + 0.5,
      respectCollision: false,
    );
    expect(state.scoresAreSimulated, isTrue);
    expect(state.isOptimized, isFalse);
    expect(state.hasCompareSnapshot, isTrue);
  });

  test('switching rooms restores BENCH OK when stash was clean', () {
    final state = AppState();
    state.createManualRoom(name: 'A', lengthMeters: 3.6, widthMeters: 3.6);
    state.runOptimization(goal: 'airflow');
    expect(state.scoresAreSimulated, isFalse);
    expect(state.isOptimized, isTrue);
    final roomA = state.activeRoomId;

    state.createManualRoom(name: 'B', lengthMeters: 4.0, widthMeters: 3.6);
    expect(state.scoresAreSimulated, isTrue);

    state.loadSavedRoom(roomA);
    expect(state.scoresAreSimulated, isFalse);
    expect(state.isOptimized, isTrue);
  });

  test('upgrade furniture is not double-counted in totalSpent', () {
    final state = AppState();
    final before = state.totalSpent;
    final price = state.upgrades.first['price'] as double;
    expect(state.toggleUpgrade(0), isTrue);
    expect(state.totalSpent, closeTo(before + price, 0.01));
  });

  test('scan session invalidate restores prior layout before room switch', () {
    final state = AppState();
    state.createManualRoom(name: 'ScanLot', lengthMeters: 3.6, widthMeters: 3.6);
    final prior = state.activeRoomLayout!;
    final priorName = prior.roomName;
    final owner = state.activeRoomId;

    state.beginScanSession(priorLayout: prior, priorScanComplete: false);
    final seed = RoomLayoutModel.emptyFromRoom(state.currentRoomData);
    state.applyScannedRoomLayout(seed, persist: false);
    expect(state.activeRoomLayout?.scanSource, isNot(prior.scanSource));

    state.createManualRoom(name: 'Other', lengthMeters: 4.0, widthMeters: 4.0);
    expect(state.takeTabNotice(), contains('Scan cancelled'));
    expect(state.isScanSessionActive, isFalse);

    state.loadSavedRoom(owner);
    expect(state.activeRoomLayout?.roomName, priorName);
  });

  test('Hub visit during scan does not stash seed into My Rooms', () {
    final state = AppState();
    state.createManualRoom(name: 'KeepMe', lengthMeters: 3.6, widthMeters: 3.6);
    final owner = state.activeRoomId;
    final prior = state.activeRoomLayout!;
    state.beginScanSession(priorLayout: prior, priorScanComplete: true);
    state.applyScannedRoomLayout(
      RoomLayoutModel.emptyFromRoom(state.currentRoomData),
      persist: false,
    );

    state.setTab(0);
    final stashed = state.savedRooms.firstWhere((r) => r.id == owner);
    expect(stashed.layout.scanSource, isNot('scan-seed'));
  });
}
