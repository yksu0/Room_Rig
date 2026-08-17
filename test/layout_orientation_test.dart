import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
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
      expect(
        LayoutOrientation.facesIntoWall(item: oriented, gridCols: cols, gridRows: rows),
        isFalse,
      );
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
