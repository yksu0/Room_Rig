// lib/services/ergonomics_optimizer.dart
import '../models/room_model.dart';
import 'ergonomics_simulator.dart';
import 'layout_optimizer_common.dart';
import 'layout_orientation.dart';

class ErgonomicsOptimizeResult {
  final List<FurnitureItem> furniture;
  final ErgonomicsMetrics metrics;
  final List<String> reasons;

  const ErgonomicsOptimizeResult({
    required this.furniture,
    required this.metrics,
    required this.reasons,
  });
}

class ErgonomicsOptimizer {
  ErgonomicsOptimizer._();

  static ErgonomicsMetrics evaluate(List<FurnitureItem> furniture) {
    return ErgonomicsSimulator.build(furniture: furniture, optimized: false).metrics;
  }

  static ErgonomicsOptimizeResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final reasons = <String>[];

    FurnitureItem? find(String id) {
      try {
        return furniture.firstWhere((f) => f.id == id);
      } catch (_) {
        return null;
      }
    }

    final targets = <String, ({double x, double y})>{};

    // Anchor a stable work cluster along the left/front work wall.
    if (find('desk') != null) {
      targets['desk'] = (x: 1.4, y: 2.0);
      reasons.add('Anchored desk with clear approach space');
    }
    final desk = targets['desk'];

    if (find('chair') != null && desk != null) {
      final deskItem = find('desk')!;
      targets['chair'] = (
        x: desk.x + (deskItem.width - 1.0) * 0.5,
        y: desk.y + deskItem.height + ErgonomicsSimulator.idealChairGap - 0.15,
      );
      reasons.add('Centered chair with knee / pull-back clearance');
    }

    if (find('monitor') != null && desk != null) {
      targets['monitor'] = (x: desk.x + 0.55, y: desk.y);
      reasons.add('Parked monitor on the desk at seated eye line');
    }
    if (find('pc') != null && desk != null) {
      targets['pc'] = (x: (desk.x - 0.85).clamp(0.0, cols - 1), y: desk.y);
      reasons.add('Moved PC into the primary reach envelope');
    }
    if (find('lamp') != null && desk != null) {
      final deskItem = find('desk')!;
      targets['lamp'] = (x: desk.x + deskItem.width - 0.15, y: desk.y);
    }

    // Clear blockers from pull-back + side aisle.
    if (find('bed') != null) {
      final bed = find('bed')!;
      targets['bed'] = (
        x: ((cols - bed.width) * 0.55).clamp(0.0, cols - bed.width),
        y: (rows - bed.height - 0.25).clamp(0.0, rows - bed.height),
      );
      reasons.add('Cleared bed off the chair pull-back path');
    }
    if (find('shelf') != null || find('bookshelf') != null) {
      final id = find('shelf') != null ? 'shelf' : 'bookshelf';
      targets[id] = (x: cols - 1, y: (rows - 2.2).clamp(3.0, rows - 1));
      reasons.add('Moved tall storage off the desk aisle');
    }
    if (find('sofa') != null) {
      targets['sofa'] = (x: 0.3, y: (rows - 2).clamp(0.0, rows - 1));
    }
    if (find('wardrobe') != null) {
      targets['wardrobe'] = (x: cols - 1, y: (rows * 0.45).clamp(2.0, rows - 2));
    }

    // Keep airflow/light fixtures from crowding the work cluster.
    if (find('window') != null) {
      final w = find('window')!;
      targets['window'] = (x: w.gridX.clamp(0.5, cols - w.width - 0.2), y: 0.0);
    }
    if (find('door') != null) {
      targets['door'] = (x: 0.0, y: (rows - 1.8).clamp(4.0, rows - 1));
      reasons.add('Kept entry door clear on the side wall');
    }
    if (find('ac') != null) {
      targets['ac'] = (x: cols - 1, y: (rows * 0.3).clamp(1.0, rows - 2));
    }
    if (find('fan') != null && desk != null) {
      targets['fan'] = (x: 0.15, y: (desk.y + 2.4).clamp(3.0, rows - 1.5));
    }
    if (find('plant') != null) {
      targets['plant'] = (x: cols - 1, y: 2.0);
    }

    final before = furniture.map((f) => f.copyWith()).toList(growable: false);
    var next = LayoutOptimizerCommon.applyTargets(
      source: furniture,
      targets: targets,
      cols: cols,
      rows: rows,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = _resolveOverlaps(next, cols, rows);
    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    LayoutOptimizerCommon.noteOrientation(reasons, before, next);
    final metrics = evaluate(next);

    if (reasons.isEmpty) {
      reasons.add('No ergonomics-critical items found to rearrange');
    }

    return ErgonomicsOptimizeResult(
      furniture: next,
      metrics: metrics,
      reasons: reasons,
    );
  }

  static List<FurnitureItem> _resolveOverlaps(
    List<FurnitureItem> items,
    double cols,
    double rows,
  ) {
    final mutable = items.map((f) => f.copyWith()).toList();
    const fixed = {'window', 'door', 'desk', 'chair'};
    for (int iter = 0; iter < 8; iter++) {
      var moved = false;
      for (int i = 0; i < mutable.length; i++) {
        for (int j = i + 1; j < mutable.length; j++) {
          final aFixed = fixed.contains(mutable[i].id);
          final bFixed = fixed.contains(mutable[j].id);
          if (aFixed && bFixed) continue;
          final a = mutable[i];
          final b = mutable[j];
          if (!_overlaps(a, b)) continue;
          final moveIdx = bFixed ? i : j;
          final keep = moveIdx == i ? b : a;
          final mover = moveIdx == i ? a : b;
          final maxX = (cols - mover.width).clamp(0.0, cols);
          final maxY = (rows - mover.height).clamp(0.0, rows);
          var nx = mover.gridX;
          var ny = mover.gridY;
          if (mover.gridX < keep.gridX) {
            nx = (keep.gridX - mover.width - 0.08).clamp(0.0, maxX);
          } else {
            nx = (keep.gridX + keep.width + 0.08).clamp(0.0, maxX);
          }
          if (_overlaps(keep, mover.copyWith(gridX: nx, gridY: ny))) {
            ny = (keep.gridY + keep.height + 0.1).clamp(0.0, maxY);
          }
          mutable[moveIdx] = mover.copyWith(
            gridX: nx.clamp(0.0, maxX),
            gridY: ny.clamp(0.0, maxY),
          );
          moved = true;
        }
      }
      if (!moved) break;
    }
    return List.unmodifiable(mutable);
  }

  static bool _overlaps(FurnitureItem a, FurnitureItem b) {
    return a.gridX < b.gridX + b.width &&
        a.gridX + a.width > b.gridX &&
        a.gridY < b.gridY + b.height &&
        a.gridY + a.height > b.gridY;
  }
}
