// lib/services/airflow_optimizer.dart
// First-pass airflow auto-arrange: move furniture, then score via voxel sim.
import '../models/room_model.dart';
import 'airflow_simulator.dart';

class AirflowOptimizeResult {
  final List<FurnitureItem> furniture;
  final AirflowMetrics metrics;
  final List<String> reasons;

  const AirflowOptimizeResult({
    required this.furniture,
    required this.metrics,
    required this.reasons,
  });
}

/// Heuristic rearrange for airflow coverage + sim-backed scoring.
class AirflowOptimizer {
  AirflowOptimizer._();

  /// Score the current layout without moving anything (field only, no tracers).
  static AirflowMetrics evaluate(List<FurnitureItem> furniture) {
    return AirflowSimulator.build(
      furniture: furniture,
      optimized: true,
      particleCount: 0,
      ambientCount: 0,
      demoBias: false,
    ).metrics;
  }

  /// Rearrange furniture for max AC throw coverage, clear lanes, wall fan.
  static AirflowOptimizeResult optimize({
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

    // 1) AC mid-depth on the longer wall (right) for max throw coverage.
    if (find('ac') != null) {
      targets['ac'] = (x: cols - 1, y: (rows * 0.4).clamp(1.0, rows - 2));
      reasons.add('Moved AC to mid long-wall for maximum throw coverage');
    }

    // 2) Window on front wall as return exhaust (offset from AC axis).
    if (find('window') != null) {
      targets['window'] = (x: 0.5, y: 0.0);
      reasons.add('Kept window as return exhaust, offset from the AC throw axis');
    }
    if (find('door') != null) {
      targets['door'] = (x: 0.0, y: (rows - 1.8).clamp(4.0, rows - 1));
      reasons.add('Anchored entry door on the side wall with a clear approach');
    }

    // 3) Work cluster (desk / chair / PC) inside the cooled sweep, left side.
    if (find('desk') != null) {
      targets['desk'] = (x: 0.3, y: (rows * 0.28).clamp(1.0, rows - 3));
      reasons.add('Placed desk inside the AC coverage cone');
    }
    final deskY = targets['desk']?.y ?? (rows * 0.28);
    if (find('chair') != null) {
      targets['chair'] = (x: 0.4, y: deskY + 1.1);
    }
    if (find('pc') != null) {
      targets['pc'] = (x: 0.2, y: deskY - 0.35);
      reasons.add('Put PC heat source inside the cooled zone');
    }

    // 4) Stand fan on desk wall — not mid-room — aiming into open floor.
    if (find('fan') != null) {
      targets['fan'] = (x: 0.15, y: (deskY + 2.2).clamp(2.0, rows - 1.5));
      reasons.add('Parked stand fan on the desk wall to mix air without blocking walkways');
    }

    // 5) Bed on far perimeter, out of primary throw.
    final bed = find('bed');
    if (bed != null) {
      targets['bed'] = (
        x: ((cols - bed.width) * 0.45).clamp(0.0, cols - bed.width),
        y: (rows - bed.height - 0.2).clamp(0.0, rows - bed.height),
      );
      reasons.add('Tucked bed along the far wall, clear of the AC throw');
    }

    // 6) Storage in a dead corner away from the throw corridor.
    if (find('shelf') != null || find('bookshelf') != null) {
      final id = find('shelf') != null ? 'shelf' : 'bookshelf';
      targets[id] = (x: 0.2, y: (rows - 1.5).clamp(0.0, rows - 1));
      reasons.add('Moved storage into a perimeter corner outside the airflow lane');
    }

    if (find('lamp') != null) {
      targets['lamp'] = (x: (cols * 0.35).clamp(1.0, cols - 1), y: 1.2);
    }

    // Sofa / plant / wardrobe: soft perimeter nudges if present.
    if (find('sofa') != null) {
      targets['sofa'] = (x: 1.0, y: (rows - 2).clamp(0.0, rows - 1));
    }
    if (find('plant') != null) {
      targets['plant'] = (x: cols - 1, y: 2.0);
    }
    if (find('wardrobe') != null) {
      targets['wardrobe'] = (x: 0.0, y: (rows * 0.55).clamp(2.0, rows - 2));
    }

    var next = _applyTargets(furniture, targets, cols, rows);
    next = _resolveOverlaps(next, cols, rows);

    final metrics = evaluate(next);

    if (reasons.isEmpty) {
      reasons.add('No airflow-critical items found to rearrange');
    }

    return AirflowOptimizeResult(
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

  /// Lightweight overlap push so Auto-Rig doesn't stack solids.
  static List<FurnitureItem> _resolveOverlaps(
    List<FurnitureItem> items,
    double cols,
    double rows,
  ) {
    final mutable = items.map((f) => f.copyWith()).toList();
    // Fixed devices can stay; push movable solids apart.
    const fixed = {'window', 'door', 'ac'};
    for (int iter = 0; iter < 8; iter++) {
      var moved = false;
      for (int i = 0; i < mutable.length; i++) {
        if (fixed.contains(mutable[i].id)) continue;
        for (int j = i + 1; j < mutable.length; j++) {
          if (fixed.contains(mutable[j].id)) continue;
          final a = mutable[i];
          final b = mutable[j];
          if (!_overlaps(a, b)) continue;

          // Push the later item down/right preferentially.
          final maxX = (cols - b.width).clamp(0.0, cols);
          final maxY = (rows - b.height).clamp(0.0, rows);
          var nx = b.gridX + 0.35;
          var ny = b.gridY;
          if (nx > maxX) {
            nx = b.gridX;
            ny = (b.gridY + 0.45).clamp(0.0, maxY);
          }
          mutable[j] = b.copyWith(gridX: nx.clamp(0.0, maxX), gridY: ny.clamp(0.0, maxY));
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
