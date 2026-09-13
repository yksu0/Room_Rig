import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:room_rig/services/item_placement_rules.dart';
import 'package:room_rig/services/layout_optimizer_common.dart';
import 'package:room_rig/services/layout_orientation.dart';

void main() {
  group('LayoutOrientation', () {
    test('sofa on south wall faces into room, not the wall', () {
      const cols = 6;
      const rows = 8;
      final sofa = FurnitureItem(
        id: 'sofa',
        name: 'Sofa',
        iconName: 'sofa',
        category: 'neutral',
        gridX: 1,
        gridY: rows - 2,
        width: 2,
        height: 1,
        yawDegrees: 0,
      );
      final oriented = LayoutOrientation.apply(
        furniture: [sofa],
        gridCols: cols,
        gridRows: rows,
      ).single;
      expect(oriented.yawDegrees, 180);
      expect(oriented.width, 2);
      expect(oriented.height, 1);
      expect(
        LayoutOrientation.facesIntoWall(item: oriented, gridCols: cols, gridRows: rows),
        isFalse,
      );
    });

    test('sofa facing TV swaps AABB so mesh matches footprint', () {
      const cols = 8;
      const rows = 8;
      final sofa = FurnitureItem(
        id: 'sofa',
        name: 'Sofa',
        iconName: 'sofa',
        category: 'neutral',
        gridX: 0,
        gridY: 3,
        width: 2,
        height: 1,
        yawDegrees: 0,
      );
      final tv = FurnitureItem(
        id: 'tv',
        name: 'TV',
        iconName: 'tv',
        category: 'lighting',
        gridX: 5,
        gridY: 3,
        width: 2,
        height: 0.45,
      );
      final oriented = LayoutOrientation.apply(
        furniture: [sofa, tv],
        gridCols: cols,
        gridRows: rows,
      );
      final s = oriented.firstWhere((f) => f.id == 'sofa');
      expect(s.yawDegrees, 90);
      expect(s.width, 1);
      expect(s.height, 2);
    });

    test('chair south of desk faces the desk', () {
      const cols = 6;
      const rows = 8;
      final desk = FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 1,
        gridY: 2,
        width: 2,
        height: 1,
      );
      final chair = FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 1.2,
        gridY: 3.4,
        yawDegrees: 0,
      );
      final oriented = LayoutOrientation.apply(
        furniture: [desk, chair],
        gridCols: cols,
        gridRows: rows,
      );
      final c = oriented.firstWhere((f) => f.id == 'chair');
      expect(c.yawDegrees, 180);
    });

    test('monitor faces desk long work edge, not sideways at PC', () {
      const cols = 8;
      const rows = 8;
      // Oriented west-wall desk: 1×2 long along the wall → work face east.
      final desk = FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 0,
        gridY: 2,
        width: 1,
        height: 2,
        yawDegrees: 90,
      );
      final monitor = FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 0.1,
        gridY: 2.6,
        width: 0.35,
        height: 0.8,
      );
      final pc = FurnitureItem(
        id: 'pc',
        name: 'PC',
        iconName: 'pc',
        category: 'airflow',
        gridX: 0,
        gridY: 2,
        width: 0.45,
        height: 0.5,
      );
      final chair = FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 1.4,
        gridY: 2.5,
        width: 1,
        height: 1,
      );
      final oriented = LayoutOrientation.apply(
        furniture: [desk, monitor, pc, chair],
        gridCols: cols,
        gridRows: rows,
      );
      final m = oriented.firstWhere((f) => f.id == 'monitor');
      final c = oriented.firstWhere((f) => f.id == 'chair');
      expect(ItemPlacementRules.deskWorkFace(desk, cols, rows), 'east');
      expect(m.yawDegrees, 90, reason: 'monitor faces east (long inward edge)');
      expect(c.yawDegrees, 270, reason: 'chair faces the screen');
      expect(m.yawDegrees, isNot(0));
    });

    test('chair seats on same work face monitor faces', () {
      const cols = 8;
      const rows = 8;
      final desk = FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 0,
        gridY: 2,
        width: 1,
        height: 2,
        yawDegrees: 90,
      );
      final monitor = FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 0.1,
        gridY: 2.6,
        width: 0.35,
        height: 0.8,
      );
      final chair = FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 3,
        gridY: 5,
        width: 1,
        height: 1,
      );
      final pose = LayoutOptimizerCommon.chairInFrontOfDesk(
        desk,
        chair,
        cols: cols.toDouble(),
        rows: rows.toDouble(),
        alignWith: monitor,
      );
      final seated = chair.copyWith(gridX: pose.x, gridY: pose.y);
      expect(
        ItemPlacementRules.chairOnWorkFace(
          seated,
          desk,
          gridCols: cols,
          gridRows: rows,
        ),
        isTrue,
      );
      expect(ItemPlacementRules.deskWorkFace(desk, cols, rows), 'east');
      expect(pose.x, greaterThan(desk.gridX + desk.width - 0.05));
      final chairCy = pose.y + chair.height * 0.5;
      final monCy = monitor.gridY + monitor.height * 0.5;
      expect((chairCy - monCy).abs(), lessThan(0.55));
    });

    test('PC stays off the chair-side of the desk', () {
      const cols = 8;
      const rows = 8;
      final desk = FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 0,
        gridY: 2,
        width: 1,
        height: 2,
        yawDegrees: 90,
      );
      final monitor = FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 0.1,
        gridY: 2.6,
        width: 0.35,
        height: 0.8,
      );
      final pc = FurnitureItem(
        id: 'pc',
        name: 'PC',
        iconName: 'pc',
        category: 'airflow',
        gridX: 3,
        gridY: 3,
        width: 0.45,
        height: 0.5,
      );
      final chair = FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 4,
        gridY: 2,
        width: 1,
        height: 1,
      );
      final mounted = LayoutOptimizerCommon.mountDeskTopItems(
        [desk, monitor, pc, chair],
        gridCols: cols,
        gridRows: rows,
      );
      final deskOut = mounted.firstWhere((f) => f.id == 'desk');
      final pcOut = mounted.firstWhere((f) => f.id == 'pc');
      final face = ItemPlacementRules.deskWorkFace(deskOut, cols, rows);
      expect(face, 'east');
      // PC must not sit on the east (chair) half of the desk.
      final pcCx = pcOut.gridX + pcOut.width * 0.5;
      final midX = deskOut.gridX + deskOut.width * 0.5;
      expect(pcCx, lessThanOrEqualTo(midX + 0.05));
    });
  });

  group('AirflowOptimizer orientation', () {
    test('optimized bed on perimeter does not face into wall', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final result = AirflowOptimizer.optimize(
        furniture: room.furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final bed = result.furniture.firstWhere((f) => f.id == 'bed');
      expect(
        LayoutOrientation.facesIntoWall(
          item: bed,
          gridCols: room.gridCols,
          gridRows: room.gridRows,
        ),
        isFalse,
      );
    });
  });
}
