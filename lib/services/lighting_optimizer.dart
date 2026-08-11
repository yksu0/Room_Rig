// lib/services/lighting_optimizer.dart
import '../models/room_model.dart';
import 'lighting_simulator.dart';

class LightingOptimizeResult {
  final List<FurnitureItem> furniture;
  final LightingMetrics metrics;
  final List<String> reasons;

  const LightingOptimizeResult({
    required this.furniture,
    required this.metrics,
    required this.reasons,
  });
}

class LightingOptimizer {
  LightingOptimizer._();

  static LightingMetrics evaluate(List<FurnitureItem> furniture) {
    return LightingSimulator.build(furniture: furniture, optimized: true).metrics;
  }

  static LightingOptimizeResult optimize({
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

    // Anchor daylight on the front wall.
    final window = find('window');
    final windowX = window != null ? window.gridX + window.width * 0.5 : cols * 0.4;
    if (window != null) {
      targets['window'] = (x: window.gridX.clamp(0.5, cols - window.width - 0.2), y: 0.0);
      reasons.add('Anchored window daylight on the front wall');
    }
    if (find('door') != null) {
      targets['door'] = (x: 0.0, y: (rows - 1.8).clamp(4.0, rows - 1));
      reasons.add('Kept entry door on the side wall');
    }

    // Desk in daylight band but offset off-axis to reduce glare.
    if (find('desk') != null) {
      final deskX = (windowX - 1.3).clamp(0.3, cols - 2.2);
      targets['desk'] = (x: deskX, y: 2.1);
      reasons.add('Moved desk into the daylight band with a glare-safe offset');
    }
    final desk = targets['desk'];
    if (find('chair') != null && desk != null) {
      targets['chair'] = (x: desk.x + 0.15, y: desk.y + 1.1);
    }
    if (find('pc') != null && desk != null) {
      targets['pc'] = (x: (desk.x - 0.7).clamp(0.0, cols - 1), y: desk.y);
    }
    if (find('monitor') != null && desk != null) {
      targets['monitor'] = (x: desk.x + 0.6, y: desk.y);
    }

    // Task lamp beside the desk (keep close; overlap pass may nudge slightly).
    if (find('lamp') != null && desk != null) {
      targets['lamp'] = (x: (desk.x + 1.05).clamp(0.0, cols - 1), y: desk.y + 0.05);
      reasons.add('Placed task lamp at the desk instead of a dark corner');
    }

    // Clear tall blockers from the window → desk corridor.
    if (find('shelf') != null || find('bookshelf') != null) {
      final id = find('shelf') != null ? 'shelf' : 'bookshelf';
      targets[id] = (x: cols - 1, y: (rows - 2.2).clamp(3.0, rows - 1));
      reasons.add('Cleared tall storage out of the daylight corridor');
    }
    if (find('wardrobe') != null) {
      targets['wardrobe'] = (x: 0.0, y: (rows * 0.55).clamp(3.0, rows - 2));
    }

    // Sleeping / lounge on the darker perimeter.
    final bed = find('bed');
    if (bed != null) {
      targets['bed'] = (
        x: ((cols - bed.width) * 0.55).clamp(0.0, cols - bed.width),
        y: (rows - bed.height - 0.25).clamp(0.0, rows - bed.height),
      );
      reasons.add('Kept bed on the darker far wall');
    }
    if (find('sofa') != null) {
      targets['sofa'] = (x: 1.0, y: (rows - 2).clamp(0.0, rows - 1));
    }

    // Keep airflow devices from stealing the daylight lane if present.
    if (find('ac') != null) {
      targets['ac'] = (x: cols - 1, y: (rows * 0.35).clamp(1.0, rows - 2));
    }
    if (find('fan') != null && desk != null) {
      targets['fan'] = (x: 0.15, y: (desk.y + 2.2).clamp(2.0, rows - 1.5));
    }
    if (find('plant') != null) {
      targets['plant'] = (x: cols - 1, y: 2.0);
    }

    var next = _applyTargets(furniture, targets, cols, rows);
    next = _resolveOverlaps(next, cols, rows);
    final metrics = evaluate(next);

    if (reasons.isEmpty) {
      reasons.add('No lighting-critical items found to rearrange');
    }

    return LightingOptimizeResult(
      furniture: next,
      metrics: metrics,
      reasons: reasons,
    );
  }

  static List<FurnitureItem> _applyTargets(
    List<FurnitureItem> source,
    Map<String, ({double x, double y})> targets,
    double cols,
    double rows,
  ) {
    return source.map((item) {
      final pos = targets[item.id];
      if (pos == null) return item.copyWith();
      final maxX = (cols - item.width).clamp(0.0, cols);
      final maxY = (rows - item.height).clamp(0.0, rows);
      return item.copyWith(
        gridX: pos.x.clamp(0.0, maxX),
        gridY: pos.y.clamp(0.0, maxY),
      );
    }).toList(growable: false);
  }

  static List<FurnitureItem> _resolveOverlaps(
    List<FurnitureItem> items,
    double cols,
    double rows,
  ) {
    final mutable = items.map((f) => f.copyWith()).toList();
    const fixed = {'window', 'door', 'lamp', 'desk'};
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
          var nx = mover.gridX + 0.35;
          var ny = mover.gridY;
          if (nx > maxX) {
            nx = mover.gridX;
            ny = (mover.gridY + 0.45).clamp(0.0, maxY);
          }
          // Prefer sliding away from the kept item.
          if (mover.gridX < keep.gridX) {
            nx = (keep.gridX - mover.width - 0.05).clamp(0.0, maxX);
          } else {
            nx = (keep.gridX + keep.width + 0.05).clamp(0.0, maxX);
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
