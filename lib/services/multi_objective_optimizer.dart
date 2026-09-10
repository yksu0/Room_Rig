import 'dart:math';

import '../models/room_model.dart';
import 'airflow_optimizer.dart';
import 'airflow_simulator.dart';
import 'benchmark_validator.dart';
import 'ergonomics_optimizer.dart';
import 'ergonomics_simulator.dart';
import 'layout_collision.dart';
import 'layout_optimizer_common.dart';
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

  /// Stable key for Auto-Rig candidate cache invalidation.
  String get cacheKey =>
      '${airflowNorm.toStringAsFixed(3)}|'
      '${lightingNorm.toStringAsFixed(3)}|'
      '${ergonomicsNorm.toStringAsFixed(3)}|'
      '${spatialNorm.toStringAsFixed(3)}';

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

  /// Weighted composite 0–100 (same mix as Hub overall score).
  final double score;

  /// 1-based rank among the scored candidate pool.
  final int rank;

  /// How many diverse candidates were kept.
  final int candidateCount;

  /// Short UI label, e.g. `Best of 4 · 84` or `Alternate #2 · 81`.
  final String rankLabel;

  const MultiObjectiveResult({
    required this.furniture,
    required this.airflowMetrics,
    required this.lightingMetrics,
    required this.ergonomicsMetrics,
    required this.reasons,
    required this.weights,
    this.score = 0,
    this.rank = 1,
    this.candidateCount = 1,
    this.rankLabel = '',
  });

  MultiObjectiveResult withRank({
    required int rank,
    required int candidateCount,
  }) {
    final label = rank <= 1
        ? 'Best of $candidateCount · ${score.round()}'
        : 'Alternate #$rank · ${score.round()}';
    return MultiObjectiveResult(
      furniture: furniture,
      airflowMetrics: airflowMetrics,
      lightingMetrics: lightingMetrics,
      ergonomicsMetrics: ergonomicsMetrics,
      reasons: reasons,
      weights: weights,
      score: score,
      rank: rank,
      candidateCount: candidateCount,
      rankLabel: label,
    );
  }
}

/// Runs each objective from the same baseline, scores proposals, keeps best-of-N.
class MultiObjectiveOptimizer {
  MultiObjectiveOptimizer._();

  static const int _maxKeptCandidates = 4;

  /// Weighted composite matching [AppState.overallScore] sim axes.
  static double scoreLayout({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final w = weights.normalized();
    final air = AirflowOptimizer.evaluate(furniture).circulationScore.clamp(0.0, 100.0);
    final light = LightingOptimizer.evaluate(furniture).exposureScore.clamp(0.0, 100.0);
    final ergo = ErgonomicsOptimizer.evaluate(furniture).comfortScore.clamp(0.0, 100.0);
    final space = SpatialAnalyzer.evaluate(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
    ).overallScore.clamp(0.0, 100.0);

    var composite = air * w.airflowNorm +
        light * w.lightingNorm +
        ergo * w.ergonomicsNorm +
        space * w.spatialNorm;

    // When spatial weight is 0, match Hub equal-ish air/light/ergo behavior.
    if (w.spatialNorm < 1e-6) {
      final t = max(0.001, w.airflowNorm + w.lightingNorm + w.ergonomicsNorm);
      composite = (air * w.airflowNorm + light * w.lightingNorm + ergo * w.ergonomicsNorm) / t;
    }

    final validation = BenchmarkValidator.validateLayout(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      mode: 'overall',
    );
    if (validation.hasHardLayoutConflicts) {
      composite -= 25;
    }
    return composite.clamp(0.0, 100.0);
  }

  static String _fingerprint(List<FurnitureItem> items) {
    final parts = items
        .map((f) => '${f.id}:${f.gridX.toStringAsFixed(2)},'
            '${f.gridY.toStringAsFixed(2)},'
            '${f.width.toStringAsFixed(2)},${f.height.toStringAsFixed(2)},'
            '${f.yawDegrees.toStringAsFixed(0)}')
        .toList()
      ..sort();
    return parts.join('|');
  }

  /// Ranked diverse candidates (best first). Used by Auto-Rig cycling.
  static List<MultiObjectiveResult> optimizeCandidates({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final baseline = furniture.map((f) => f.copyWith()).toList(growable: false);
    final w = weights.normalized();

    final proposals = <({List<FurnitureItem> items, List<String> reasons, String tag})>[];

    void addProposal(List<FurnitureItem> items, List<String> reasons, String tag) {
      proposals.add((items: items, reasons: reasons, tag: tag));
    }

    // Domain optimizers (always generate — score picks the winner).
    final air = AirflowOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    addProposal(air.furniture, air.reasons.take(3).toList(), 'airflow');

    final light = LightingOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    addProposal(light.furniture, light.reasons.take(3).toList(), 'lighting');

    final ergo = ErgonomicsOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    addProposal(ergo.furniture, ergo.reasons.take(3).toList(), 'ergonomics');

    final space = SpatialOptimizer.optimize(
      furniture: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    addProposal(space.furniture, space.reasons.take(3).toList(), 'spatial');

    // Weighted blend of the three classic goals.
    final blended = _blendLayouts(
      baseline: baseline,
      airflow: air.furniture,
      lighting: light.furniture,
      ergonomics: ergo.furniture,
      weights: w,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    var blendItems = blended;
    final blendReasons = <String>[
      'Blended independent Auto-Rig proposals',
      'Weight mix ${w.summaryLabel}',
    ];
    if (w.spatialNorm >= 0.15) {
      final spaced = SpatialOptimizer.optimize(
        furniture: blendItems,
        gridCols: gridCols,
        gridRows: gridRows,
      );
      blendItems = spaced.furniture;
      blendReasons.addAll(spaced.reasons.take(2));
    }
    addProposal(blendItems, blendReasons, 'blend');

    // Deterministic zone-rule packs (different work-cluster biases).
    for (final bias in WorkClusterBias.values) {
      final packed = _rulesPack(
        baseline: baseline,
        gridCols: gridCols,
        gridRows: gridRows,
        bias: bias,
      );
      addProposal(
        packed.items,
        [
          'Rules pack (${bias.name}) — desk cluster + lounge zones',
          ...packed.reasons.take(3),
        ],
        'rules_${bias.name}',
      );
    }

    // Wall-side variants: flip primary desk to the opposite side wall.
    final eastFlip = _wallSideVariant(
      baseline: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
      preferEast: true,
    );
    if (eastFlip != null) {
      addProposal(eastFlip.items, eastFlip.reasons, 'wall_east');
    }
    final westFlip = _wallSideVariant(
      baseline: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
      preferEast: false,
    );
    if (westFlip != null) {
      addProposal(westFlip.items, westFlip.reasons, 'wall_west');
    }

    final scored = <MultiObjectiveResult>[];
    final seen = <String>{};

    for (final p in proposals) {
      final packed = _pack(
        furniture: p.items,
        weights: w,
        reasons: [
          'Weight mix ${w.summaryLabel}',
          'Candidate: ${p.tag}',
          ...p.reasons,
        ],
        gridCols: gridCols,
        gridRows: gridRows,
      );
      final fp = _fingerprint(packed.furniture);
      if (!seen.add(fp)) continue;

      final score = scoreLayout(
        furniture: packed.furniture,
        gridCols: gridCols,
        gridRows: gridRows,
        weights: w,
      );
      scored.add(
        MultiObjectiveResult(
          furniture: packed.furniture,
          airflowMetrics: packed.airflowMetrics,
          lightingMetrics: packed.lightingMetrics,
          ergonomicsMetrics: packed.ergonomicsMetrics,
          reasons: [
            ...packed.reasons,
            'Scored ${score.toStringAsFixed(1)} under ${w.summaryLabel}',
          ],
          weights: w,
          score: score,
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // Keep top diverse layouts (fingerprint already unique; cap count).
    final kept = scored.take(_maxKeptCandidates).toList(growable: false);
    final n = kept.length;
    return [
      for (var i = 0; i < n; i++) kept[i].withRank(rank: i + 1, candidateCount: n),
    ];
  }

  /// Best scored candidate (Bench / one-shot callers).
  static MultiObjectiveResult optimize({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final ranked = optimizeCandidates(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    if (ranked.isEmpty) {
      return _pack(
        furniture: furniture,
        weights: weights.normalized(),
        reasons: const ['No candidates — returned baseline pack'],
        gridCols: gridCols,
        gridRows: gridRows,
      );
    }
    return ranked.first;
  }

  static ({List<FurnitureItem> items, List<String> reasons}) _rulesPack({
    required List<FurnitureItem> baseline,
    required int gridCols,
    required int gridRows,
    required WorkClusterBias bias,
  }) {
    final targets = <String, ({double x, double y})>{};
    final reasons = <String>[];
    reasons.addAll(
      LayoutOptimizerCommon.planWorkCluster(
        furniture: baseline,
        targets: targets,
        gridCols: gridCols,
        gridRows: gridRows,
        bias: bias,
      ),
    );
    LayoutOptimizerCommon.planPerimeterStorage(
      furniture: baseline,
      targets: targets,
      gridCols: gridCols,
      gridRows: gridRows,
      reasons: reasons,
    );
    var next = LayoutOptimizerCommon.applyTargets(
      source: baseline,
      targets: targets,
      cols: gridCols.toDouble(),
      rows: gridRows.toDouble(),
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = LayoutOptimizerCommon.relinkPairedLayout(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return (items: next, reasons: reasons);
  }

  /// Force the work desk onto the east or west wall, then relink the cluster.
  static ({List<FurnitureItem> items, List<String> reasons})? _wallSideVariant({
    required List<FurnitureItem> baseline,
    required int gridCols,
    required int gridRows,
    required bool preferEast,
  }) {
    final desk0 = LayoutOptimizerCommon.findDesk(baseline);
    if (desk0 == null || desk0.locked) return null;

    final packed = _rulesPack(
      baseline: baseline,
      gridCols: gridCols,
      gridRows: gridRows,
      bias: WorkClusterBias.ergonomics,
    );
    var next = packed.items.map((f) => f.copyWith()).toList();
    final desk = LayoutOptimizerCommon.findDesk(next);
    if (desk == null) return null;

    final maxX = (gridCols - desk.width).clamp(0.0, gridCols.toDouble());
    final pinnedX = preferEast ? maxX : 0.0;
    if ((desk.gridX - pinnedX).abs() < 0.05) {
      // Already on that wall — not a distinct candidate.
      return null;
    }
    final di = next.indexWhere((f) => f.id == desk.id);
    if (di < 0) return null;
    next[di] = desk.copyWith(gridX: pinnedX);

    next = LayoutOptimizerCommon.relinkPairedLayout(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    next = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return (
      items: next,
      reasons: [
        preferEast
            ? 'Work desk pinned to the east wall'
            : 'Work desk pinned to the west wall',
        ...packed.reasons.take(2),
      ],
    );
  }

  static MultiObjectiveResult _pack({
    required List<FurnitureItem> furniture,
    required MultiObjectiveWeights weights,
    required List<String> reasons,
    required int gridCols,
    required int gridRows,
  }) {
    var mounted = LayoutOptimizerCommon.mountDeskTopItems(
      furniture,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    mounted = LayoutOptimizerCommon.relinkPairedLayout(
      items: mounted,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    mounted = LayoutOptimizerCommon.resolveLayoutConflicts(
      items: mounted,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    // Conflicts can shove the cluster — re-assert desk orientation, seats, and yaw.
    mounted = LayoutOptimizerCommon.relinkPairedLayout(
      items: mounted,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    mounted = LayoutOrientation.apply(
      furniture: mounted,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    final air = AirflowOptimizer.evaluate(mounted);
    final light = LightingOptimizer.evaluate(mounted);
    final ergo = ErgonomicsOptimizer.evaluate(mounted);
    final score = scoreLayout(
      furniture: mounted,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    return MultiObjectiveResult(
      furniture: mounted,
      airflowMetrics: air,
      lightingMetrics: light,
      ergonomicsMetrics: ergo,
      reasons: reasons,
      weights: weights,
      score: score,
      rank: 1,
      candidateCount: 1,
      rankLabel: 'Best of 1 · ${score.round()}',
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
