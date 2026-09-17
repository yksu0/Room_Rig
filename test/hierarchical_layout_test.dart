import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/upgrade_catalog.dart';
import 'package:room_rig/services/hierarchical_layout.dart';
import 'package:room_rig/services/item_placement_rules.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';
import 'package:room_rig/services/placement_catalog.dart';

void main() {
  test('PlacementCatalog covers every catalog + upgrade id', () {
    for (final e in RigCatalog.items) {
      final f = e.toFurniture(id: e.baseId, gridX: 1, gridY: 1);
      final spec = PlacementCatalog.of(f);
      expect(spec.id, isNot('unknown'), reason: e.baseId);
    }
    for (final u in UpgradeCatalog.specs) {
      final f = FurnitureItem(
        id: u.furnitureId,
        name: u.name,
        iconName: u.iconName,
        category: u.type,
        gridX: 1,
        gridY: 1,
        width: 1,
        height: 1,
      );
      final spec = PlacementCatalog.of(f);
      expect(spec.id, isNot('unknown'), reason: u.furnitureId);
    }
  });

  test('hierarchy ranks anchors before majors before attached', () {
    expect(
      PlacementCatalog.hierarchyRank(PlacementClass.aAnchor),
      lessThan(PlacementCatalog.hierarchyRank(PlacementClass.bMajor)),
    );
    expect(
      PlacementCatalog.hierarchyRank(PlacementClass.bMajor),
      lessThan(PlacementCatalog.hierarchyRank(PlacementClass.eAttached)),
    );
  });

  test('Auto-Rig keeps bed touching at least one wall', () {
    for (final preset in RoomPreset.values) {
      final room = RoomPresets.getPreset(preset);
      if (!room.furniture.any((f) => f.iconName == 'bed' || f.id.contains('bed'))) {
        continue;
      }
      final result = MultiObjectiveOptimizer.optimize(
        furniture: room.furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: const MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7),
      );
      final bed = result.furniture.firstWhere(
        (f) => f.iconName == 'bed' || f.id.contains('bed'),
      );
      expect(
        HierarchicalLayout.touchesWall(bed, room.gridCols, room.gridRows),
        isTrue,
        reason:
            '$preset bed at (${bed.gridX},${bed.gridY}) '
            'dist=${ItemPlacementRules.wallDistance(bed, room.gridCols, room.gridRows)}',
      );
    }
  });

  test('floating bed is pinned to a wall by HierarchicalLayout.enforce', () {
    const cols = 8;
    const rows = 8;
    final items = [
      FurnitureItem(
        id: 'door',
        name: 'Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: 6,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 0,
        gridY: 1,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'bed',
        name: 'Bed',
        iconName: 'bed',
        category: 'neutral',
        gridX: 3,
        gridY: 3,
        width: 2,
        height: 2,
      ),
    ];
    final out = HierarchicalLayout.enforce(
      items: items,
      gridCols: cols,
      gridRows: rows,
    );
    final bed = out.firstWhere((f) => f.id == 'bed');
    expect(HierarchicalLayout.touchesWall(bed, cols, rows), isTrue);
  });

  test('chair is functional not physical child; PC is B beside desk association', () {
    final chair = PlacementCatalog.of(
      FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 1,
        gridY: 2,
        width: 1,
        height: 1,
      ),
    );
    expect(chair.physicalParent, isNull);
    expect(chair.spatialParent, 'desk');
    expect(chair.relative, RelativePlacement.inFrontOf);
    expect(chair.klass, PlacementClass.cPeripheral);

    final pc = PlacementCatalog.of(
      FurnitureItem(
        id: 'pc',
        name: 'PC',
        iconName: 'pc',
        category: 'airflow',
        gridX: 0,
        gridY: 0,
        width: 1,
        height: 1,
      ),
    );
    expect(pc.klass, PlacementClass.bMajor);
    expect(pc.isPhysicalChild, isFalse);
    expect(pc.spatialParent, 'desk');
    expect(pc.relative, RelativePlacement.beside);
    expect(pc.facing, FaceTarget.none);
    expect(pc.ventClearance, greaterThan(0));
  });

  test('upgrade aliases resolve to canonical ids', () {
    final arm = PlacementCatalog.of(
      FurnitureItem(
        id: 'upg_monitor_arm_1',
        name: 'Monitor Arm',
        iconName: 'monitorArm',
        category: 'ergonomics',
        gridX: 0,
        gridY: 0,
        width: 1,
        height: 1,
      ),
    );
    expect(arm.id, 'upg_monitor_arm');
    expect(arm.klass, PlacementClass.eAttached);
    expect(arm.physicalParent, 'desk');
  });

  test('TV wall-mounted uses must wall', () {
    final tv = PlacementCatalog.of(
      FurnitureItem(
        id: 'tv',
        name: 'TV',
        iconName: 'tv',
        category: 'neutral',
        gridX: 5,
        gridY: 2,
        width: 1,
        height: 1,
      ),
    );
    expect(tv.wall, WallRequirement.must);
    expect(tv.surface, PlacementSurface.wall);
  });

  test('preset floorLamp icon is not the desk task lamp', () {
    final floor = PlacementCatalog.of(
      FurnitureItem(
        id: 'lamp',
        name: 'Floor Lamp',
        iconName: 'floorLamp',
        category: 'lighting',
        gridX: 5,
        gridY: 0,
        width: 1,
        height: 1,
      ),
    );
    expect(floor.id, 'floor_lamp');
    expect(floor.klass, PlacementClass.cPeripheral);
    expect(floor.participatesInMainLayout, isTrue);
  });
}
