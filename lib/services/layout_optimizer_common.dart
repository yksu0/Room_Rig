// lib/services/layout_optimizer_common.dart
import '../models/room_model.dart';
import '../widgets/furniture_shapes.dart';
import 'layout_orientation.dart';

/// Shared post-pass every domain optimizer runs after x/y placement.
class LayoutOptimizerCommon {
  LayoutOptimizerCommon._();

  static List<FurnitureItem> applyTargets({
    required List<FurnitureItem> source,
    required Map<String, ({double x, double y})> targets,
    required double cols,
    required double rows,
    required int gridCols,
    required int gridRows,
  }) {
    var next = source.map((item) {
      final pos = targets[item.id];
      if (pos == null) return item.copyWith();
      final maxX = (cols - item.width).clamp(0.0, cols);
      final maxY = (rows - item.height).clamp(0.0, rows);
      return item.copyWith(
        gridX: pos.x.clamp(0.0, maxX),
        gridY: pos.y.clamp(0.0, maxY),
      );
    }).toList(growable: false);

    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return next;
  }

  /// Append once when any seated item was re-aimed away from a wall.
  static void noteOrientation(
    List<String> reasons,
    List<FurnitureItem> before,
    List<FurnitureItem> after,
  ) {
    for (int i = 0; i < before.length; i++) {
      final a = after[i];
      if ((before[i].yawDegrees - a.yawDegrees).abs() > 0.01 &&
          (FurnitureShapes.showsFacing(FurnitureShapes.kindOf(a)) || a.id == 'bed')) {
        reasons.add('Turned seating and fans to face into the room — not the wall');
        return;
      }
    }
  }
}
