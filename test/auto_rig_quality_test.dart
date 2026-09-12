import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/benchmark_validator.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

/// Keep Auto-Rigging until every catalog / upgrade path stays conflict-free
/// and never drops furniture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void expectCleanAutoRig(
    List<FurnitureItem> before,
    List<FurnitureItem> after, {
    required int gridCols,
    required int gridRows,
    required String label,
  }) {
    expect(after.map((f) => f.id).toSet(), before.map((f) => f.id).toSet(),
        reason: '$label must keep every furniture id');
    expect(after.length, before.length, reason: '$label must not drop items');

    final hard = LayoutCollision.findConflicts(
      furniture: after,
      gridCols: gridCols,
      gridRows: gridRows,
    ).where(
      (c) =>
          c.kind == LayoutConflictKind.overlap ||
          c.kind == LayoutConflictKind.blockedOpening,
    );
    expect(hard, isEmpty, reason: '$label hard conflicts: $hard');

    final validation = BenchmarkValidator.validateLayout(
      furniture: after,
      gridCols: gridCols,
      gridRows: gridRows,
      mode: 'overall',
    );
    expect(validation.hasHardLayoutConflicts, isFalse,
        reason: '$label validator hard conflicts');

    // Desk-tops that have a host must sit on a desk/table.
    for (final item in after) {
      if (!SurfaceMounts.isDeskTopItem(item)) continue;
      final host = SurfaceMounts.hostUnder(item, after);
      if (host == null) continue;
      expect(SurfaceMounts.isDeskHost(host), isTrue,
          reason: '$label ${item.id} host ${host.id} should be a desk');
    }

    // Bed and sofa must not occupy the same cells.
    final beds = after.where((f) => f.iconName == 'bed' || f.id.contains('bed'));
    final sofas = after.where(
      (f) => f.iconName == 'sofa' || f.id.contains('sofa') || f.name.toLowerCase().contains('sofa'),
    );
    for (final bed in beds) {
      for (final sofa in sofas) {
        expect(
          LayoutCollision.blocks(bed, sofa, after),
          isFalse,
          reason: '$label bed ${bed.id} stacked on sofa ${sofa.id}',
        );
      }
    }
  }

  group('preset Auto-Rig stays clean', () {
    for (final preset in RoomPreset.values) {
      for (final goal in const [null, 'airflow', 'lighting', 'ergonomics', 'spatial']) {
        test('$preset goal=${goal ?? "balanced"}', () {
          final state = AppState();
          state.selectPreset(preset);
          state.acceptPresetAsReady();
          final before = state.furniture.map((f) => f.copyWith()).toList();
          state.runOptimization(goal: goal);
          expectCleanAutoRig(
            before,
            state.furniture,
            gridCols: state.currentRoomData.gridCols,
            gridRows: state.currentRoomData.gridRows,
            label: '$preset/$goal',
          );
        });
      }
    }
  });

  test('add every catalog item on a large room then Auto-Rig stays clean', () {
    const cols = 12;
    const rows = 12;
    final base = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final furniture = base.furniture.map((f) => f.copyWith()).toList();
    final used = furniture.map((f) => f.id).toSet();

    for (final entry in RigCatalog.items) {
      var id = entry.baseId;
      var n = 2;
      while (used.contains(id)) {
        id = '${entry.baseId}_$n';
        n++;
      }
      final cell = LayoutCollision.findEmptyCell(
        furniture: furniture,
        gridCols: cols,
        gridRows: rows,
        width: entry.width,
        height: entry.height,
        preferInterior: true,
      );
      if (cell == null) continue;
      furniture.add(
        entry.toFurniture(id: id, gridX: cell.gridX, gridY: cell.gridY),
      );
      used.add(id);
    }

    expect(furniture.length, greaterThan(RigCatalog.items.length));
    final before = furniture.map((f) => f.copyWith()).toList();
    final result = MultiObjectiveOptimizer.optimize(
      furniture: before,
      gridCols: cols,
      gridRows: rows,
      weights: const MultiObjectiveWeights(
        airflow: 0.7,
        lighting: 0.5,
        ergonomics: 0.6,
        spatial: 0.4,
      ),
    );
    expectCleanAutoRig(
      before,
      result.furniture,
      gridCols: cols,
      gridRows: rows,
      label: 'full-catalog-large',
    );
  });

  test('crowded 6x8 Auto-Rig keeps every id even if space is tight', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.acceptPresetAsReady();
    for (final entry in RigCatalog.items) {
      state.addCatalogFurniture(entry);
    }
    final beforeIds = state.furniture.map((f) => f.id).toSet();
    state.runOptimization();
    expect(state.furniture.map((f) => f.id).toSet(), beforeIds,
        reason: 'crowded Auto-Rig must never drop furniture');
  });

  test('add each catalog item alone then Auto-Rig', () {
    for (final entry in RigCatalog.items) {
      final state = AppState();
      state.selectPreset(RoomPreset.homeOffice);
      state.acceptPresetAsReady();
      final id = state.addCatalogFurniture(entry);
      expect(id, isNotNull, reason: 'could not place ${entry.baseId}');
      final before = state.furniture.map((f) => f.copyWith()).toList();
      state.runOptimization(goal: 'airflow');
      expectCleanAutoRig(
        before,
        state.furniture,
        gridCols: state.currentRoomData.gridCols,
        gridRows: state.currentRoomData.gridRows,
        label: 'solo-${entry.baseId}',
      );
    }
  });

  test('place upgrades then Auto-Rig keeps upg_* ids', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.acceptPresetAsReady();

    for (var i = 0; i < state.upgrades.length; i++) {
      state.toggleUpgrade(i);
    }
    final before = state.furniture.map((f) => f.copyWith()).toList();
    expect(before.any((f) => f.id.startsWith('upg_')), isTrue);

    state.runOptimization();
    expectCleanAutoRig(
      before,
      state.furniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      label: 'upgrades',
    );
    expect(state.furniture.where((f) => f.id.startsWith('upg_')).length,
        before.where((f) => f.id.startsWith('upg_')).length);
  });

  test('add then remove catalog pieces across Auto-Rig cycles', () {
    final state = AppState();
    state.selectPreset(RoomPreset.studioApartment);
    state.acceptPresetAsReady();

    final added = <String>[];
    for (final entry in const ['tv', 'space_heater', 'floor_lamp', 'wardrobe', 'plant']) {
      final catalog = RigCatalog.items.firstWhere((e) => e.baseId == entry);
      final id = state.addCatalogFurniture(catalog);
      if (id != null) added.add(id);
      final before = state.furniture.map((f) => f.copyWith()).toList();
      state.runOptimization();
      expectCleanAutoRig(
        before,
        state.furniture,
        gridCols: state.currentRoomData.gridCols,
        gridRows: state.currentRoomData.gridRows,
        label: 'add-$entry',
      );
    }

    for (final id in added.reversed) {
      state.deleteFurniture(id);
      final before = state.furniture.map((f) => f.copyWith()).toList();
      state.runOptimization(goal: 'lighting');
      expectCleanAutoRig(
        before,
        state.furniture,
        gridCols: state.currentRoomData.gridCols,
        gridRows: state.currentRoomData.gridRows,
        label: 'remove-$id',
      );
    }
  });

  test('bed+sofa room never stacks after MultiObjectiveOptimizer', () {
    final room = RoomPresets.getPreset(RoomPreset.studioApartment);
    final furniture = [
      ...room.furniture.map((f) => f.copyWith()),
      FurnitureItem(
        id: 'extra_sofa',
        name: 'Sofa',
        iconName: 'sofa',
        category: 'neutral',
        gridX: 3,
        gridY: 5,
        width: 2,
        height: 1,
      ),
    ];
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(airflow: 0.7, lighting: 0.5, ergonomics: 0.6),
    );
    expectCleanAutoRig(
      furniture,
      result.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      label: 'bed-sofa-multi',
    );
  });
}
