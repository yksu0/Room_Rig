// lib/services/lighting_optimizer.dart
// Auto-Rig lighting arrange: daylight band + glare offset + task lamp (IES).
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'layout_collision.dart';
import 'layout_optimizer_common.dart';
import 'layout_orientation.dart';
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
    return LightingSimulator.build(furniture: furniture, optimized: false).metrics;
  }

  static LightingOptimizeResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final reasons = <String>[];
    final targets = <String, ({double x, double y})>{};

    final window = LayoutOptimizerCommon.findWindow(furniture);
    if (window != null) {
      targets[window.id] = (
        x: window.gridX.clamp(0.5, cols - window.width - 0.2),
        y: 0.0,
      );
      reasons.add('Anchored window daylight on the front wall');
    }

    final door = LayoutOptimizerCommon.findDoor(furniture);
    if (door != null) {
      targets[door.id] = (x: 0.0, y: (rows - 1.8).clamp(4.0, rows - 1));
      reasons.add('Kept entry door clear on the side wall');
    }

    reasons.addAll(
      LayoutOptimizerCommon.planWorkCluster(
        furniture: furniture,
        targets: targets,
        gridCols: gridCols,
        gridRows: gridRows,
        bias: WorkClusterBias.lighting,
      ),
    );

    LayoutOptimizerCommon.planPerimeterStorage(
      furniture: furniture,
      targets: targets,
      gridCols: gridCols,
      gridRows: gridRows,
      reasons: reasons,
    );

    final desk = LayoutOptimizerCommon.findDesk(furniture);
    final deskY = targets[desk?.id]?.y ?? desk?.gridY ?? 2.0;
    final ac = LayoutOptimizerCommon.firstWhere(furniture, SurfaceMounts.isVent);
    if (ac != null) {
      targets[ac.id] = (x: cols - 1, y: (rows * 0.35).clamp(1.0, rows - 2));
    }
    final fan = LayoutOptimizerCommon.firstWhere(
      furniture,
      (f) => f.iconName == 'fan' || '${f.id} ${f.name}'.toLowerCase().contains('fan'),
    );
    if (fan != null) {
      targets[fan.id] = (x: 0.15, y: (deskY + 2.2).clamp(2.0, rows - 1.5));
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
    next = LayoutOptimizerCommon.mountDeskTopItems(next);
    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    LayoutOptimizerCommon.noteOrientation(reasons, before, next);
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

  static List<FurnitureItem> _resolveOverlaps(
    List<FurnitureItem> items,
    double cols,
    double rows,
  ) {
    final mutable = items.map((f) => f.copyWith()).toList();
    for (int iter = 0; iter < 8; iter++) {
      var moved = false;
      for (int i = 0; i < mutable.length; i++) {
        for (int j = i + 1; j < mutable.length; j++) {
          final a = mutable[i];
          final b = mutable[j];
          final aFixed = SurfaceMounts.isStructuralMount(a) || SurfaceMounts.isDeskHost(a);
          final bFixed = SurfaceMounts.isStructuralMount(b) || SurfaceMounts.isDeskHost(b);
          if (aFixed && bFixed) continue;
          if (!LayoutCollision.blocks(a, b, mutable)) continue;
          final moveIdx = bFixed ? i : j;
          final keep = moveIdx == i ? b : a;
          final mover = moveIdx == i ? a : b;
          final maxX = (cols - mover.width).clamp(0.0, cols);
          final maxY = (rows - mover.height).clamp(0.0, rows);
          var nx = mover.gridX;
          var ny = mover.gridY;
          if (mover.gridX < keep.gridX) {
            nx = (keep.gridX - mover.width - 0.05).clamp(0.0, maxX);
          } else {
            nx = (keep.gridX + keep.width + 0.05).clamp(0.0, maxX);
          }
          if (nx > maxX) {
            ny = (mover.gridY + 0.45).clamp(0.0, maxY);
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
}
