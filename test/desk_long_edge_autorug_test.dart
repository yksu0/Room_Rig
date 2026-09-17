import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/item_placement_rules.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  const weights =
      MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7);

  test('Auto-Rig orients side-wall desk long-along-wall; chair on long face', () {
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
    FurnitureItem? monitor;
    for (final f in result.furniture) {
      if (f.iconName == 'monitor') {
        monitor = f;
        break;
      }
    }

    // 2×1 catalog desk on a side wall becomes 1×2 (long along the wall).
    expect(desk.height, greaterThan(desk.width + 0.2));
    expect(
      ItemPlacementRules.deskFlushToWall(desk, room.gridCols, room.gridRows),
      isTrue,
    );
    final face =
        ItemPlacementRules.deskWorkFace(desk, room.gridCols, room.gridRows);
    expect(face == 'east' || face == 'west', isTrue, reason: 'inward long face, got $face');
    expect(
      ItemPlacementRules.chairOnWorkFace(
        chair,
        desk,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ),
      isTrue,
      reason: 'chair (${chair.gridX},${chair.gridY}) desk '
          '${desk.width}x${desk.height}@(${desk.gridX},${desk.gridY}) face=$face',
    );
    if (monitor != null) {
      expect(monitor.yawDegrees, ItemPlacementRules.yawFacingWorkFace(face));
      // Screen must not point sideways along the wall (old PC-facing bug).
      if (face == 'east' || face == 'west') {
        expect(monitor.yawDegrees == 0 || monitor.yawDegrees == 180, isFalse);
      }
    }
  });
}
