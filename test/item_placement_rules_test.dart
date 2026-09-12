import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/item_placement_rules.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

/// Human layout sanity: chair at desk, bed clear of desk, shelves on walls.
void main() {
  const weights = MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7);

  test('every catalog + upgrade id has an arrangement note', () {
    for (final entry in RigCatalog.items) {
      final note = ItemPlacementRules.arrangementNote(entry.baseId);
      expect(note, isNotEmpty, reason: entry.baseId);
      expect(note.toLowerCase(), isNot(contains('iso 9241')));
    }
    for (final id in const [
      'upg_fan',
      'upg_purifier',
      'upg_light_bar',
      'upg_floor_lamp',
      'upg_monitor_arm',
      'upg_cable_tray',
      'upg_mat',
      'upg_blinds',
    ]) {
      expect(ItemPlacementRules.arrangementNote(id), isNotEmpty);
    }
  });

  test('Auto-Rig keeps chair in front of desk', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final result = MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final desk = result.furniture.firstWhere(
      (f) => f.iconName == 'desk' || f.id.contains('desk'),
    );
    final chair = result.furniture.firstWhere(
      (f) => f.iconName == 'chair' || f.id.contains('chair'),
    );
    expect(
      ItemPlacementRules.deskFlushToWall(desk, room.gridCols, room.gridRows),
      isTrue,
      reason: 'desk (${desk.gridX},${desk.gridY}) must be flush to a side wall',
    );
    expect(
      ItemPlacementRules.chairOnWorkFace(
        chair,
        desk,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ),
      isTrue,
      reason: 'chair (${chair.gridX},${chair.gridY}) desk (${desk.gridX},${desk.gridY})',
    );

    FurnitureItem? monitor;
    for (final f in result.furniture) {
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      if (hay.contains('monitor arm')) continue;
      if (f.iconName == 'monitor' || hay.contains('monitor')) {
        monitor = f;
        break;
      }
    }
    if (monitor != null) {
      final face = ItemPlacementRules.deskWorkFace(desk, room.gridCols, room.gridRows);
      expect(monitor.yawDegrees, ItemPlacementRules.yawFacingWorkFace(face));
      final ccx = chair.gridX + chair.width * 0.5;
      final ccy = chair.gridY + chair.height * 0.5;
      final mcx = monitor.gridX + monitor.width * 0.5;
      final mcy = monitor.gridY + monitor.height * 0.5;
      if (face == 'east' || face == 'west') {
        expect(
          (ccy - mcy).abs(),
          lessThan(0.85),
          reason: 'chair aligned with monitor on $face face',
        );
      } else {
        expect(
          (ccx - mcx).abs(),
          lessThan(0.85),
          reason: 'chair aligned with monitor on $face face',
        );
      }
    }
  });

  test('Auto-Rig pins desk to a side wall on home office', () {
    final room = RoomPresets.getPreset(RoomPreset.homeOffice);
    final result = MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final desk = result.furniture.firstWhere(
      (f) => f.iconName == 'desk' || f.id.contains('desk'),
    );
    final chair = result.furniture.firstWhere(
      (f) => f.iconName == 'chair' || f.id.contains('chair'),
    );
    expect(
      ItemPlacementRules.deskFlushToWall(desk, room.gridCols, room.gridRows),
      isTrue,
      reason: 'desk (${desk.gridX},${desk.gridY})',
    );
    expect(
      ItemPlacementRules.chairOnWorkFace(
        chair,
        desk,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ),
      isTrue,
      reason: 'chair (${chair.gridX},${chair.gridY}) desk (${desk.gridX},${desk.gridY})',
    );
  });

  test('Auto-Rig keeps bed clear of desk work zone', () {
    const cols = 10;
    const rows = 10;
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'door',
        name: 'Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: 7,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 1,
        gridY: 1,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 3,
        gridY: 3,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'bed',
        name: 'Bed',
        iconName: 'bed',
        category: 'neutral',
        gridX: 2,
        gridY: 2,
        width: 2,
        height: 2,
      ),
    ];
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: cols,
      gridRows: rows,
      weights: weights,
    );
    final desk = result.furniture.firstWhere((f) => f.id == 'desk');
    final bed = result.furniture.firstWhere((f) => f.id == 'bed');
    expect(
      ItemPlacementRules.hasClearGap(
        bed,
        desk,
        ItemPlacementRules.deskBedClearance * 0.85,
      ),
      isTrue,
      reason: 'bed (${bed.gridX},${bed.gridY}) desk (${desk.gridX},${desk.gridY})',
    );
  });

  test('Auto-Rig keeps shelf on a wall, not mid-room', () {
    const cols = 10;
    const rows = 10;
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'door',
        name: 'Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: 7,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 1,
        gridY: 1,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 1,
        gridY: 3,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'shelf',
        name: 'Shelf',
        iconName: 'shelf',
        category: 'neutral',
        gridX: 4,
        gridY: 4,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'bed',
        name: 'Bed',
        iconName: 'bed',
        category: 'neutral',
        gridX: 6,
        gridY: 6,
        width: 2,
        height: 2,
      ),
    ];
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: cols,
      gridRows: rows,
      weights: weights,
    );
    final shelf = result.furniture.firstWhere((f) => f.id == 'shelf');
    final wallDist = ItemPlacementRules.wallDistance(shelf, cols, rows);
    expect(
      wallDist,
      lessThanOrEqualTo(ItemPlacementRules.wallFlushTolerance + 0.05),
      reason: 'shelf at (${shelf.gridX},${shelf.gridY}) wallDist=$wallDist',
    );
  });

  test('Auto-Rig keeps sofa↔TV near preferred viewing distance', () {
    const cols = 10;
    const rows = 10;
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'door',
        name: 'Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: 8,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'window',
        name: 'Window',
        iconName: 'window',
        category: 'lighting',
        gridX: 4,
        gridY: 0,
        width: 2,
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
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 0,
        gridY: 3,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'sofa',
        name: 'Sofa',
        iconName: 'sofa',
        category: 'neutral',
        gridX: 1,
        gridY: 5,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'tv',
        name: 'TV',
        iconName: 'tv',
        category: 'neutral',
        gridX: 8,
        gridY: 5,
        width: 1,
        height: 1,
      ),
    ];
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: cols,
      gridRows: rows,
      weights: weights,
    );
    final sofa = result.furniture.firstWhere((f) => f.id == 'sofa');
    final tv = result.furniture.firstWhere((f) => f.id == 'tv');
    expect(
      ItemPlacementRules.sofaTvDistanceOk(sofa, tv, tolerance: 1.0),
      isTrue,
      reason:
          'sofa (${sofa.gridX},${sofa.gridY}) tv (${tv.gridX},${tv.gridY}) '
          'dist=${ItemPlacementRules.sofaTvCenterDistance(sofa, tv).toStringAsFixed(2)}',
    );
  });

  test('Auto-Rig keeps wardrobe front swing clear', () {
    const cols = 10;
    const rows = 10;
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'door',
        name: 'Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: 8,
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
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 0,
        gridY: 3,
        width: 1,
        height: 1,
      ),
      FurnitureItem(
        id: 'wardrobe',
        name: 'Wardrobe',
        iconName: 'wardrobe',
        category: 'neutral',
        gridX: 4,
        gridY: 4,
        width: 1,
        height: 2,
      ),
      FurnitureItem(
        id: 'plant',
        name: 'Plant',
        iconName: 'plant',
        category: 'neutral',
        gridX: 5,
        gridY: 4,
        width: 1,
        height: 1,
      ),
    ];
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: cols,
      gridRows: rows,
      weights: weights,
    );
    final wardrobe = result.furniture.firstWhere((f) => f.id == 'wardrobe');
    expect(
      ItemPlacementRules.hasWardrobeFrontClearance(
        wardrobe,
        result.furniture,
        cols,
        rows,
      ),
      isTrue,
      reason: 'wardrobe at (${wardrobe.gridX},${wardrobe.gridY})',
    );
  });
}
