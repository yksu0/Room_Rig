import 'dart:math';

import '../models/room_model.dart';
import 'airflow_optimizer.dart';
import 'airflow_simulator.dart';
import 'ergonomics_optimizer.dart';
import 'ergonomics_simulator.dart';
import 'layout_collision.dart';
import 'layout_orientation.dart';
import 'lighting_optimizer.dart';
import 'lighting_simulator.dart';
import 'spatial_analyzer.dart';

class MultiObjectiveWeights {
  final double airflow;
  final double lighting;
  final double ergonomics;
  final double spatial;

  const MultiObjectiveWeights({
    required this.airflow,
    required this.lighting,
    required this.ergonomics,
    this.spatial = 0,
  });

  double get total => max(0.001, airflow + lighting + ergonomics + spatial);

  double get airflowNorm => airflow / total;
  double get lightingNorm => lighting / total;
  double get ergonomicsNorm => ergonomics / total;
  double get spatialNorm => spatial / total;

  String get summaryLabel {
    final a = (airflowNorm * 100).round();
    final l = (lightingNorm * 100).round();
    final e = (ergonomicsNorm * 100).round();
    final s = (spatialNorm * 100).round();
    if (spatial > 0) return 'Air $a% · Light $l% · Ergo $e% · Space $s%';
    return 'Air $a% · Light $l% · Ergo $e%';
  }

  MultiObjectiveWeights normalized() => MultiObjectiveWeights(
        airflow: airflowNorm,
        lighting: lightingNorm,
        ergonomics: ergonomicsNorm,
        spatial: spatialNorm,
      );

  /// Dominant objective if one weight owns ≥62% of the mix.
  String? get dominantGoal {
    final n = normalized();
    if (n.airflow >= 0.62) return 'airflow';
    if (n.lighting >= 0.62) return 'lighting';
    if (n.ergonomics >= 0.62) return 'ergonomics';
    if (n.spatial >= 0.62) return 'spatial';
    return null;
  }
}

class MultiObjectiveResult {
  final List<FurnitureItem> furniture;
  final AirflowMetrics airflowMetrics;
  final LightingMetrics lightingMetrics;
  final ErgonomicsMetrics ergonomicsMetrics;
  final List<String> reasons;
  final MultiObjectiveWeights weights;

  const MultiObjectiveResult({
    required this.furniture,
    required this.airflowMetrics,
    required this.lightingMetrics,
    required this.ergonomicsMetrics,
    required this.reasons,
    required this.weights,
  });
}

/// Runs each objective from the same baseline, then blends poses by weight.
class MultiObjectiveOptimizer {
  MultiObjectiveOptimizer._();

  static MultiObjectiveResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final baseline = furniture.map((f) => f.copyWith()).toList(growable: false);
    final w = weights.normalized();
    final reasons = <String>[
      'Weight mix ${w.summaryLabel}',
    ];

    final dominant = w.dominantGoal;
    if (dominant == 'airflow') {
      final air = AirflowOptimizer.optimize(
        furniture: baseline,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      reasons.addAll(air.reasons.take(4));
      return _pack(
        furniture: air.furniture,
        weights: w,
        reasons: reasons,
      );
    }
    if (dominant == 'lighting') {
      final light = LightingOptimizer.optimize(
        furniture: baseline,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      reasons.addAll(light.reasons.take(4));
      return _pack(
        furniture: light.furniture,
        weights: w,
        reasons: reasons,
      );
    }
    if (dominant == 'ergonomics') {
      final ergo = ErgonomicsOptimizer.optimize(
        furniture: baseline,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      reasons.addAll(ergo.reasons.take(4));
      return _pack(
        furniture: ergo.furniture,
        weights: w,
        reasons: reasons,
      );
    }
    if (dominant == 'spatial') {
      final space = SpatialOptimizer.optimize(
        furniture: baseline,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      reasons.addAll(space.reasons.take(4));
      return _pack(
        furniture: space.furniture,
        weights: w,
        reasons: reasons,
      );
    }

    final air = AirflowOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    final light = LightingOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    final ergo = ErgonomicsOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    reasons.add('Blended independent Auto-Rig proposals (not sequential overwrite)');
    if (w.airflowNorm >= 0.2) reasons.addAll(air.reasons.take(2).map((r) => 'Airflow: $r'));
    if (w.lightingNorm >= 0.2) reasons.addAll(light.reasons.take(2).map((r) => 'Lighting: $r'));
    if (w.ergonomicsNorm >= 0.2) reasons.addAll(ergo.reasons.take(2).map((r) => 'Ergo: $r'));

    var blended = _blendLayouts(
      baseline: baseline,
      airflow: air.furniture,
      lighting: light.furniture,
      ergonomics: ergo.furniture,
      weights: w,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    if (w.spatialNorm >= 0.15) {
      final space = SpatialOptimizer.optimize(
        furniture: blended,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      blended = space.furniture;
      reasons.addAll(space.reasons.take(2).map((r) => 'Space: $r'));
    }

    blended = LayoutOrientation.apply(
      furniture: blended,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    return _pack(
      furniture: blended,
      weights: w,
      reasons: reasons,
    );
  }

  static MultiObjectiveResult _pack({
    required List<FurnitureItem> furniture,
    required MultiObjectiveWeights weights,
    required List<String> reasons,
  }) {
    return MultiObjectiveResult(
      furniture: furniture,
      airflowMetrics: AirflowOptimizer.evaluate(furniture),
      lightingMetrics: LightingOptimizer.evaluate(furniture),
      ergonomicsMetrics: ErgonomicsOptimizer.evaluate(furniture),
      reasons: reasons,
      weights: weights,
    );
  }

  static List<FurnitureItem> _blendLayouts({
    required List<FurnitureItem> baseline,
    required List<FurnitureItem> airflow,
    required List<FurnitureItem> lighting,
    required List<FurnitureItem> ergonomics,
    required MultiObjectiveWeights weights,
    required int gridCols,
    required int gridRows,
  }) {
    final airMap = {for (final f in airflow) f.id: f};
    final lightMap = {for (final f in lighting) f.id: f};
    final ergoMap = {for (final f in ergonomics) f.id: f};

    final blended = <FurnitureItem>[];
    for (final base in baseline) {
      if (base.locked) {
        blended.add(base.copyWith());
        continue;
      }

      final a = airMap[base.id] ?? base;
      final l = lightMap[base.id] ?? base;
      final e = ergoMap[base.id] ?? base;

      final wa = weights.airflowNorm;
      final wl = weights.lightingNorm;
      final we = weights.ergonomicsNorm;

      var x = a.gridX * wa + l.gridX * wl + e.gridX * we;
      var y = a.gridY * wa + l.gridY * wl + e.gridY * we;
      // Footprint / yaw: pick from the highest-weight proposal.
      final primary = wa >= wl && wa >= we
          ? a
          : (wl >= we ? l : e);
      final yaw = primary.yawDegrees;
      final width = primary.width;
      final height = primary.height;

      x = x.clamp(0.0, max(0.0, gridCols - width));
      y = y.clamp(0.0, max(0.0, gridRows - height));

      blended.add(
        base.copyWith(
          gridX: LayoutCollision.snap(x),
          gridY: LayoutCollision.snap(y),
          width: width,
          height: height,
          yawDegrees: yaw,
        ),
      );
    }

    return _resolveOverlaps(blended, gridCols: gridCols, gridRows: gridRows);
  }

  static List<FurnitureItem> _resolveOverlaps(
    List<FurnitureItem> items, {
    required int gridCols,
    required int gridRows,
  }) {
    var next = items.map((f) => f.copyWith()).toList();
    for (int pass = 0; pass < 3; pass++) {
      for (int i = 0; i < next.length; i++) {
        final item = next[i];
        if (item.locked || LayoutCollision.nonColliding.contains(item.id)) continue;
        final resolved = LayoutCollision.resolveMove(
          id: item.id,
          proposedX: item.gridX,
          proposedY: item.gridY,
          furniture: next,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        next[i] = item.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
      }
    }
    return next;
  }
}
