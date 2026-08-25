// lib/services/airflow_optimizer.dart
// Auto-Rig airflow arrange: HVAC throw + cooled work zone, then voxel score.
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'airflow_simulator.dart';
import 'layout_collision.dart';
import 'layout_optimizer_common.dart';
import 'layout_orientation.dart';

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

  static AirflowMetrics evaluate(List<FurnitureItem> furniture) {
    return AirflowSimulator.build(
      furniture: furniture,
      optimized: false,
      particleCount: 0,
      ambientCount: 0,
    ).metrics;
  }

  static AirflowOptimizeResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final reasons = <String>[];
    final targets = <String, ({double x, double y})>{};

    final ac = LayoutOptimizerCommon.firstWhere(furniture, SurfaceMounts.isVent);
    if (ac != null) {
      // Mid-depth on the longer wall → widest throw coverage (ASHRAE).
      targets[ac.id] = (x: cols - 1, y: (rows * 0.4).clamp(1.0, rows - 2));
      reasons.add('Moved AC to mid long-wall for maximum throw coverage');
    }

    final window = LayoutOptimizerCommon.findWindow(furniture);
    if (window != null) {
      targets[window.id] = (
        x: window.gridX.clamp(0.5, cols - window.width - 0.2),
        y: 0.0,
      );
      reasons.add('Kept the window as a pressure-neutral opening on the front wall');
    }

    final intake = LayoutOptimizerCommon.firstWhere(furniture, SurfaceMounts.isIntake);
    if (intake != null) {
      targets[intake.id] = (x: cols - 1, y: (rows * 0.15).clamp(0.2, rows - 2));
      reasons.add('Parked intake away from extract so supply can pressurize the room');
    }
    final exhaust = LayoutOptimizerCommon.firstWhere(furniture, SurfaceMounts.isExhaust);
    if (exhaust != null) {
      targets[exhaust.id] = (x: 0.0, y: (rows * 0.55).clamp(1.0, rows - 2));
      reasons.add('Moved exhaust opposite the AC throw so extract does not short-circuit');
    }

    final door = LayoutOptimizerCommon.findDoor(furniture);
    if (door != null) {
      targets[door.id] = (x: 0.0, y: (rows - 1.8).clamp(4.0, rows - 1));
      reasons.add('Anchored entry door with a clear approach aisle');
    }

    reasons.addAll(
      LayoutOptimizerCommon.planWorkCluster(
        furniture: furniture,
        targets: targets,
        gridCols: gridCols,
        gridRows: gridRows,
        bias: WorkClusterBias.airflow,
      ),
    );

    final fan = LayoutOptimizerCommon.firstWhere(
      furniture,
      (f) => f.iconName == 'fan' || '${f.id} ${f.name}'.toLowerCase().contains('fan'),
    );
    if (fan != null) {
      // East wall, mid-depth — mixes the room without blocking the entry approach.
      final fanY = (rows * 0.55).clamp(2.5, rows - 1.5);
      targets[fan.id] = (x: cols - 1.0, y: fanY);
      reasons.add('Stand fan on the far wall to mix air without blocking the entry');
    }

    LayoutOptimizerCommon.planPerimeterStorage(
      furniture: furniture,
      targets: targets,
      gridCols: gridCols,
      gridRows: gridRows,
      reasons: reasons,
    );

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
    next = LayoutOptimizerCommon.mountDeskTopItems(next);
    // Keep wall fans pinned after overlap nudges.
    next = next.map((f) {
      final isFan = f.iconName == 'fan' || '${f.id} ${f.name}'.toLowerCase().contains('fan');
      if (!isFan || f.locked) return f;
      final pos = targets[f.id];
      if (pos == null) return f;
      return f.copyWith(gridX: pos.x, gridY: f.gridY.clamp(pos.y - 0.5, pos.y + 0.5));
    }).toList(growable: false);
    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = _resolveOpeningBlocks(next, gridCols, gridRows);
    next = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    // Re-pin HVAC targets after collision nudges.
    next = next.map((f) {
      if (f.locked) return f;
      final pos = targets[f.id];
      if (pos == null) return f;
      if (SurfaceMounts.isVent(f) ||
          SurfaceMounts.isIntake(f) ||
          SurfaceMounts.isExhaust(f)) {
        return f.copyWith(gridX: pos.x, gridY: pos.y);
      }
      final isFan = f.iconName == 'fan' || '${f.id} ${f.name}'.toLowerCase().contains('fan');
      if (!isFan) return f;
      return f.copyWith(gridX: pos.x, gridY: f.gridY.clamp(pos.y - 0.5, pos.y + 0.5));
    }).toList(growable: false);
    LayoutOptimizerCommon.noteOrientation(reasons, before, next);

    final beforeMetrics = evaluate(before);
    final metrics = evaluate(next);
    if (metrics.circulationScore + 0.5 < beforeMetrics.circulationScore) {
      return AirflowOptimizeResult(
        furniture: before,
        metrics: beforeMetrics,
        reasons: [
          ...reasons,
          'Kept your layout — auto-arrange would not improve airflow',
        ],
      );
    }

    if (reasons.isEmpty) {
      reasons.add('No airflow-critical items found to rearrange');
    }

    return AirflowOptimizeResult(
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
    for (int iter = 0; iter < 8; iter++) {
      var moved = false;
      for (int i = 0; i < mutable.length; i++) {
        if (SurfaceMounts.isStructuralMount(mutable[i])) continue;
        for (int j = i + 1; j < mutable.length; j++) {
          if (SurfaceMounts.isStructuralMount(mutable[j])) continue;
          final a = mutable[i];
          final b = mutable[j];
          if (!LayoutCollision.blocks(a, b, mutable)) continue;
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

  /// Nudge movable items that block doors or windows after overlap resolution.
  static List<FurnitureItem> _resolveOpeningBlocks(
    List<FurnitureItem> items,
    int gridCols,
    int gridRows,
  ) {
    final mutable = items.map((f) => f.copyWith()).toList();
    for (int pass = 0; pass < 6; pass++) {
      final conflicts = LayoutCollision.findConflicts(
        furniture: mutable,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      final blocked = conflicts.where((c) => c.kind == LayoutConflictKind.blockedOpening).toList();
      if (blocked.isEmpty) break;

      for (final conflict in blocked) {
        final blockerId = conflict.itemIds.firstWhere(
          (id) => !id.contains('door') && !id.contains('window'),
          orElse: () => conflict.itemIds.first,
        );
        final idx = mutable.indexWhere((f) => f.id == blockerId);
        if (idx < 0) continue;
        final item = mutable[idx];
        if (item.locked || SurfaceMounts.isStructuralMount(item)) continue;
        final maxX = (gridCols - item.width).clamp(0.0, gridCols.toDouble());
        final maxY = (gridRows - item.height).clamp(0.0, gridRows.toDouble());
        var nx = (item.gridX + 0.5).clamp(0.0, maxX);
        var ny = (item.gridY - 0.6).clamp(0.0, maxY);
        if (ny == item.gridY) ny = (item.gridY + 0.6).clamp(0.0, maxY);
        mutable[idx] = item.copyWith(gridX: nx, gridY: ny);
      }
    }
    return List.unmodifiable(mutable);
  }
}
