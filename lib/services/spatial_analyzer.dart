// lib/services/spatial_analyzer.dart
// Walkable-floor estimate — occupancy, door aisle, unused corners. Not CAD.
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/surface_mount.dart';
import 'layout_collision.dart';
import 'layout_optimizer_common.dart';
import 'layout_orientation.dart';

class SpatialMetrics {
  final double walkableRatio;
  final double utilizationScore;
  final double accessibilityScore;
  final double overallScore;
  final double largestAisleCells;
  final double doorBlockedRatio;
  final int unusedCornerCount;
  final List<String> notes;
  final List<bool> occupied;

  const SpatialMetrics({
    required this.walkableRatio,
    required this.utilizationScore,
    required this.accessibilityScore,
    required this.overallScore,
    required this.largestAisleCells,
    required this.doorBlockedRatio,
    required this.unusedCornerCount,
    required this.notes,
    required this.occupied,
  });
}

class SpatialOptimizeResult {
  final List<FurnitureItem> furniture;
  final SpatialMetrics metrics;
  final List<String> reasons;

  const SpatialOptimizeResult({
    required this.furniture,
    required this.metrics,
    required this.reasons,
  });
}

class SpatialAnalyzer {
  SpatialAnalyzer._();

  static SpatialMetrics evaluate({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final occupied = List<bool>.filled(gridCols * gridRows, false);
    for (final f in furniture) {
      if (f.hidden) continue;
      if (LayoutCollision.skipsFloorOccupancy(f)) continue;
      final x0 = f.gridX.floor().clamp(0, gridCols - 1);
      final y0 = f.gridY.floor().clamp(0, gridRows - 1);
      final x1 = (f.gridX + f.width).ceil().clamp(0, gridCols);
      final y1 = (f.gridY + f.height).ceil().clamp(0, gridRows);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          occupied[y * gridCols + x] = true;
        }
      }
    }

    final total = gridCols * gridRows;
    var blocked = 0;
    for (final v in occupied) {
      if (v) blocked++;
    }
    final walkable = ((total - blocked) / total).clamp(0.0, 1.0);
    final occupancy = 1.0 - walkable;

    // Sweet spot: a lived-in room is ~30–55% occupied.
    final utilization = occupancy < 0.18
        ? (occupancy / 0.18) * 70
        : occupancy <= 0.55
            ? 70 + (0.55 - occupancy) / 0.37 * 30
            : (1.0 - occupancy).clamp(0.0, 1.0) / 0.45 * 70;

    final aisle = _largestAisle(occupied, gridCols, gridRows);
    final door = _doorBlockedRatio(furniture, occupied, gridCols, gridRows);
    final unusedCorners = _emptyCorners(occupied, gridCols, gridRows);

    var access = 100.0;
    access -= door * 55;
    if (aisle < 1.0) {
      access -= 25;
    } else if (aisle < 1.5) {
      access -= 10;
    }
    access = access.clamp(0.0, 100.0);

    final overall = (utilization * 0.45 + access * 0.55).clamp(0.0, 100.0);

    final notes = <String>[];
    if (door > 0.4) {
      notes.add(
        'Furniture blocks about ${(door * 100).round()}% of the door aisle.',
      );
    } else if (door > 0.05) {
      notes.add('Keep a clearer path from the door into the room.');
    }
    if (aisle < 1.0) {
      notes.add('Largest walkway is under ${RoomScale.formatMeters(RoomScale.cellMeters)} — too tight.');
    } else {
      notes.add(
        'Largest aisle is about ${RoomScale.formatCellsAsMeters(aisle)}.',
      );
    }
    notes.add(
      '${(walkable * 100).round()}% of the floor is walkable.',
    );
    if (unusedCorners >= 3 && occupancy < 0.25) {
      notes.add('Corners are empty — the room is under-used.');
    } else if (occupancy > 0.62) {
      notes.add('The floor is packed — pull large pieces toward the walls.');
    }

    return SpatialMetrics(
      walkableRatio: walkable,
      utilizationScore: utilization.clamp(0.0, 100.0),
      accessibilityScore: access,
      overallScore: overall,
      largestAisleCells: aisle,
      doorBlockedRatio: door,
      unusedCornerCount: unusedCorners,
      notes: notes,
      occupied: occupied,
    );
  }

  static double _largestAisle(List<bool> occupied, int cols, int rows) {
    var best = 0;
    for (int y = 0; y < rows; y++) {
      var run = 0;
      for (int x = 0; x < cols; x++) {
        if (!occupied[y * cols + x]) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
      }
    }
    for (int x = 0; x < cols; x++) {
      var run = 0;
      for (int y = 0; y < rows; y++) {
        if (!occupied[y * cols + x]) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
      }
    }
    return best.toDouble();
  }

  static double _doorBlockedRatio(
    List<FurnitureItem> furniture,
    List<bool> occupied,
    int cols,
    int rows,
  ) {
    FurnitureItem? door;
    for (final f in furniture) {
      if (f.iconName == 'door' || f.id.contains('door')) {
        door = f;
        break;
      }
    }
    if (door == null) return 0;
    final inward = door.gridY <= 1
        ? 1
        : door.gridY + door.height >= rows - 1
            ? -1
            : door.gridX <= 1
                ? 1
                : -1;
    final alongX = door.gridY <= 1 || door.gridY + door.height >= rows - 1;
    var cells = 0;
    var blocked = 0;
    for (int step = 1; step <= 2; step++) {
      for (int k = 0; k < 2; k++) {
        final x = alongX
            ? (door.gridX + k).floor()
            : (door.gridX + inward * step).floor();
        final y = alongX
            ? (door.gridY + inward * step).floor()
            : (door.gridY + k).floor();
        if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
        cells++;
        if (occupied[y * cols + x]) blocked++;
      }
    }
    if (cells == 0) return 0;
    return blocked / cells;
  }

  static int _emptyCorners(List<bool> occupied, int cols, int rows) {
    bool empty(int x, int y) {
      if (x < 0 || y < 0 || x >= cols || y >= rows) return false;
      return !occupied[y * cols + x];
    }

    var n = 0;
    if (empty(0, 0) && empty(1, 0) && empty(0, 1)) n++;
    if (empty(cols - 1, 0) && empty(cols - 2, 0) && empty(cols - 1, 1)) n++;
    if (empty(0, rows - 1) && empty(1, rows - 1) && empty(0, rows - 2)) n++;
    if (empty(cols - 1, rows - 1) &&
        empty(cols - 2, rows - 1) &&
        empty(cols - 1, rows - 2)) {
      n++;
    }
    return n;
  }
}

class SpatialOptimizer {
  SpatialOptimizer._();

  static SpatialMetrics evaluate({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) =>
      SpatialAnalyzer.evaluate(
        furniture: furniture,
        gridCols: gridCols,
        gridRows: gridRows,
      );

  /// Nudge pieces off the door aisle and toward walls when the floor is jammed.
  static SpatialOptimizeResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    var next = furniture.map((f) => f.copyWith()).toList();
    final reasons = <String>[];
    final before = SpatialAnalyzer.evaluate(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    FurnitureItem? door;
    for (final f in next) {
      if (f.iconName == 'door' || f.id.contains('door')) {
        door = f;
        break;
      }
    }

    if (door != null && before.doorBlockedRatio > 0.15) {
      final doorBox = door;
      for (int i = 0; i < next.length; i++) {
        final item = next[i];
        if (item.id == doorBox.id) continue;
        if (item.locked || LayoutCollision.skipsFloorOccupancy(item)) continue;
        if (SurfaceMounts.isDeskTopItem(item) || SurfaceMounts.isDeskHost(item)) continue;
        final approach = doorBox.copyWith(
          gridX: doorBox.gridX,
          gridY: doorBox.gridY,
          width: doorBox.width + 1.2,
          height: doorBox.height + 1.2,
        );
        if (!LayoutCollision.overlaps(item, approach) &&
            !LayoutCollision.overlaps(item, doorBox)) {
          continue;
        }
        final spot = LayoutCollision.findEmptyCell(
          furniture: next.where((f) => f.id != item.id).toList(),
          gridCols: gridCols,
          gridRows: gridRows,
          width: item.width,
          height: item.height,
        );
        if (spot == null) continue;
        next[i] = item.copyWith(gridX: spot.gridX, gridY: spot.gridY);
        reasons.add('Moved ${item.name} off the door aisle.');
      }
    }

    if (before.walkableRatio < 0.42) {
      for (int i = 0; i < next.length; i++) {
        final item = next[i];
        if (item.locked || LayoutCollision.skipsFloorOccupancy(item)) continue;
        if (SurfaceMounts.isDeskTopItem(item) || SurfaceMounts.isDeskHost(item)) continue;
        if (item.width < 1.5 && item.height < 1.5) continue;
        final spot = LayoutCollision.findEmptyCell(
          furniture: next.where((f) => f.id != item.id).toList(),
          gridCols: gridCols,
          gridRows: gridRows,
          width: item.width,
          height: item.height,
        );
        if (spot == null) continue;
        final closerToWall = [
              spot.gridX,
              spot.gridY,
              gridCols - item.width - spot.gridX,
              gridRows - item.height - spot.gridY,
            ].reduce((a, b) => a < b ? a : b) <
            [
              item.gridX,
              item.gridY,
              gridCols - item.width - item.gridX,
              gridRows - item.height - item.gridY,
            ].reduce((a, b) => a < b ? a : b);
        if (!closerToWall) continue;
        if ((spot.gridX - item.gridX).abs() < 0.01 &&
            (spot.gridY - item.gridY).abs() < 0.01) {
          continue;
        }
        next[i] = item.copyWith(gridX: spot.gridX, gridY: spot.gridY);
        reasons.add('Parked ${item.name} closer to a wall.');
        if (reasons.length >= 3) break;
      }
    }

    if (reasons.isEmpty) {
      reasons.add('Walkways were already clear enough to leave in place.');
    }

    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = LayoutOptimizerCommon.mountDeskTopItems(next);
    next = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    final metrics = SpatialAnalyzer.evaluate(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return SpatialOptimizeResult(
      furniture: next,
      metrics: metrics,
      reasons: reasons,
    );
  }
}
