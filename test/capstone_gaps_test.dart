import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_scale.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/services/spatial_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  test('RoomScale maps meters to clamped cells', () {
    expect(RoomScale.cellsFromMeters(3.6), 6);
    expect(RoomScale.cellsFromMeters(4.8), 8);
    expect(RoomScale.cellsFromMeters(1.0), RoomScale.minCells);
    expect(RoomScale.formatCellsAsMeters(2), '1.2 m');
  });

  test('currentRoomData uses layout coverage, not a frozen 6x8 preset', () {
    final state = AppState();
    state.createManualRoom(name: 'Studio', lengthMeters: 5.4, widthMeters: 3.6, heightMeters: 2.7);
    expect(state.currentRoomData.name, 'Studio');
    expect(state.currentRoomData.gridCols, 9);
    expect(state.currentRoomData.gridRows, 6);
    expect(state.furniture.any((f) => f.iconName == 'door'), isTrue);
    expect(state.furniture.any((f) => f.iconName == 'window'), isTrue);
    expect(state.activeRoomLayout?.scanSource, 'manual');
  });

  test('commitScannedRoomLayout keeps measured grid size', () {
    final state = AppState();
    final layout = RoomLayoutModel(
      roomName: 'Walked',
      dimensions: const RoomDimensions(lengthMeters: 4.8, widthMeters: 3.6, heightMeters: 2.7),
      coverageGrid: CoverageGrid.empty(cols: 8, rows: 6),
      objects: const [],
      updatedAt: DateTime.now().toUtc(),
      scanSource: 'test',
    );
    state.commitScannedRoomLayout(layout, inputProviderId: 'test');
    expect(state.currentRoomData.gridCols, 8);
    expect(state.currentRoomData.gridRows, 6);
    expect(state.scanComplete, isTrue);
  });

  test('ghost drag follows overlap then snaps back on release', () {
    final state = AppState();
    final desk = state.furniture.firstWhere((f) => f.id == 'desk');
    final chair = state.furniture.firstWhere((f) => f.id == 'chair');
    state.selectFurniture(desk.id);
    state.beginFurnitureGesture();
    state.moveFurniture(desk.id, chair.gridX, chair.gridY);
    expect(state.dragPoseBlocked, isTrue);
    expect(LayoutCollision.itemCollides(state.furniture.firstWhere((f) => f.id == 'desk'), state.furniture), isTrue);
    state.endFurnitureGesture();
    final after = state.furniture.firstWhere((f) => f.id == 'desk');
    expect(LayoutCollision.itemCollides(after, state.furniture), isFalse);
  });

  test('resize and custom object land on the empty room', () {
    final state = AppState();
    state.createManualRoom(name: 'Empty', lengthMeters: 4.8, widthMeters: 4.8);
    final id = state.addCustomFurniture(name: 'Box', width: 1, height: 1);
    expect(id, isNotNull);
    expect(state.resizeFurniture(id!, dWidth: 0.25), isTrue);
    final box = state.furniture.firstWhere((f) => f.id == id);
    expect(box.width, 1.25);
    expect(box.name, 'Box');
  });

  test('spatial analyzer scores walkable floor and Auto-Rig uses it', () {
    final state = AppState();
    final metrics = SpatialAnalyzer.evaluate(
      furniture: state.furniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
    );
    expect(metrics.walkableRatio, greaterThan(0.2));
    expect(metrics.overallScore, inInclusiveRange(0, 100));
    expect(state.spatialScore, inInclusiveRange(0, 100));
    state.runOptimization(goal: 'spatial');
    expect(state.isOptimized, isTrue);
    expect(state.hasCompareSnapshot, isTrue);
    expect(state.buildShareReport().contains('Space:'), isTrue);
  });

  test('My Rooms duplicate and load keep the previous lot', () {
    final state = AppState();
    final firstName = state.currentRoomData.name;
    state.createManualRoom(name: 'Lot B', lengthMeters: 3.6, widthMeters: 3.6);
    expect(state.savedRooms.length, greaterThanOrEqualTo(1));
    expect(state.currentRoomData.name, 'Lot B');
    expect(state.duplicateActiveRoom(), isTrue);
    expect(state.currentRoomData.name.contains('Copy'), isTrue);
    final original = state.savedRooms.firstWhere((r) => r.name == firstName, orElse: () => state.savedRooms.first);
    state.loadSavedRoom(original.id);
    expect(state.savedRooms.map((r) => r.name), isNotEmpty);
  });

  test('pending catalog item is a centre ghost until Place', () {
    final state = AppState();
    final lamp = RigCatalog.items.firstWhere((e) => e.baseId == 'lamp');
    final id = state.addCatalogFurniture(lamp, pending: true);
    expect(id, isNotNull);
    expect(state.hasPendingPlacement, isTrue);
    final ghost = state.furniture.firstWhere((f) => f.id == id);
    expect(ghost.gridX, closeTo((state.currentRoomData.gridCols - lamp.width) / 2, 0.5));
    expect(ghost.gridY, closeTo((state.currentRoomData.gridRows - lamp.height) / 2, 0.5));

    state.moveFurniture(id!, 0, 7);
    expect(state.confirmPendingPlacement(), isTrue);
    expect(state.hasPendingPlacement, isFalse);
    expect(state.furniture.any((f) => f.id == id), isTrue);

    final fan = RigCatalog.items.firstWhere((e) => e.baseId == 'fan');
    final ghostId = state.addCatalogFurniture(fan, pending: true);
    expect(ghostId, isNotNull);
    state.cancelPendingPlacement();
    expect(state.hasPendingPlacement, isFalse);
    expect(state.furniture.any((f) => f.id == ghostId), isFalse);
  });
}
