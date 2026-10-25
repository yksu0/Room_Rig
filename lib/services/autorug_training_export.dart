// Structured Auto-Rig ranker training examples (JSON / JSONL).
// Labels come from existing simulators + MultiObjectiveOptimizer.scoreLayout.
import 'dart:math';

import '../models/room_model.dart';
import '../models/sim_room_bounds.dart';
import 'airflow_optimizer.dart';
import 'benchmark_validator.dart';
import 'ergonomics_optimizer.dart';
import 'lighting_optimizer.dart';
import 'multi_objective_optimizer.dart';
import 'spatial_analyzer.dart';

/// Compact furniture pose used in ranker training dumps.
class AutoRigLayoutItem {
  final String id;
  final String category;
  final String iconName;
  final double gridX;
  final double gridY;
  final double width;
  final double height;
  final double yawDegrees;

  const AutoRigLayoutItem({
    required this.id,
    required this.category,
    required this.iconName,
    required this.gridX,
    required this.gridY,
    required this.width,
    required this.height,
    required this.yawDegrees,
  });

  factory AutoRigLayoutItem.fromFurniture(FurnitureItem f) => AutoRigLayoutItem(
        id: f.id,
        category: f.category,
        iconName: f.iconName,
        gridX: f.gridX,
        gridY: f.gridY,
        width: f.width,
        height: f.height,
        yawDegrees: f.yawDegrees,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'iconName': iconName,
        'gridX': double.parse(gridX.toStringAsFixed(3)),
        'gridY': double.parse(gridY.toStringAsFixed(3)),
        'width': double.parse(width.toStringAsFixed(3)),
        'height': double.parse(height.toStringAsFixed(3)),
        'yawDegrees': double.parse(yawDegrees.toStringAsFixed(1)),
      };
}

/// One labeled layout for pointwise score regression / ranking pairs.
class AutoRigTrainingExample {
  final String roomId;
  final String layoutId;
  final int gridCols;
  final int gridRows;
  final List<AutoRigLayoutItem> anchors;
  final MultiObjectiveWeights weights;
  final List<AutoRigLayoutItem> items;
  final double airflow;
  final double lighting;
  final double ergonomics;
  final double spatial;
  final double overall;
  final bool collisionOk;
  final String proposalTag;
  final String split;

  const AutoRigTrainingExample({
    required this.roomId,
    required this.layoutId,
    required this.gridCols,
    required this.gridRows,
    required this.anchors,
    required this.weights,
    required this.items,
    required this.airflow,
    required this.lighting,
    required this.ergonomics,
    required this.spatial,
    required this.overall,
    required this.collisionOk,
    required this.proposalTag,
    required this.split,
  });

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'layout_id': layoutId,
        'grid_cols': gridCols,
        'grid_rows': gridRows,
        'anchors': anchors.map((a) => a.toJson()).toList(),
        'weights': {
          'airflow': double.parse(weights.airflowNorm.toStringAsFixed(4)),
          'lighting': double.parse(weights.lightingNorm.toStringAsFixed(4)),
          'ergonomics': double.parse(weights.ergonomicsNorm.toStringAsFixed(4)),
          'spatial': double.parse(weights.spatialNorm.toStringAsFixed(4)),
        },
        'layout': {'items': items.map((i) => i.toJson()).toList()},
        'labels': {
          'airflow': double.parse(airflow.toStringAsFixed(2)),
          'lighting': double.parse(lighting.toStringAsFixed(2)),
          'ergonomics': double.parse(ergonomics.toStringAsFixed(2)),
          'spatial': double.parse(spatial.toStringAsFixed(2)),
          'overall': double.parse(overall.toStringAsFixed(2)),
          'collision_ok': collisionOk,
          'proposal_tag': proposalTag,
        },
        'split': split,
      };
}

/// Pairwise preference within one room + weight mix (stage-1: higher overall wins).
class AutoRigPreferencePair {
  final String roomId;
  final MultiObjectiveWeights weights;
  final String layoutAId;
  final String layoutBId;
  final String winnerId;
  final String split;

  const AutoRigPreferencePair({
    required this.roomId,
    required this.weights,
    required this.layoutAId,
    required this.layoutBId,
    required this.winnerId,
    required this.split,
  });

  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'weights': {
          'airflow': double.parse(weights.airflowNorm.toStringAsFixed(4)),
          'lighting': double.parse(weights.lightingNorm.toStringAsFixed(4)),
          'ergonomics': double.parse(weights.ergonomicsNorm.toStringAsFixed(4)),
          'spatial': double.parse(weights.spatialNorm.toStringAsFixed(4)),
        },
        'layout_a_id': layoutAId,
        'layout_b_id': layoutBId,
        'winner_id': winnerId,
        'split': split,
      };
}

class AutoRigTrainingExport {
  AutoRigTrainingExport._();

  static const _anchorIds = {'door', 'window'};

  static const weightMixes = <MultiObjectiveWeights>[
    MultiObjectiveWeights(airflow: 1, lighting: 1, ergonomics: 1, spatial: 0),
    MultiObjectiveWeights(
        airflow: 0.5, lighting: 0.2, ergonomics: 0.2, spatial: 0.1),
    MultiObjectiveWeights(
        airflow: 0.2, lighting: 0.5, ergonomics: 0.2, spatial: 0.1),
    MultiObjectiveWeights(
        airflow: 0.2, lighting: 0.2, ergonomics: 0.5, spatial: 0.1),
    MultiObjectiveWeights(
        airflow: 0.25, lighting: 0.25, ergonomics: 0.25, spatial: 0.25),
  ];

  static bool isAnchor(FurnitureItem f) =>
      _anchorIds.contains(f.id) ||
      f.iconName == 'door' ||
      f.iconName == 'window';

  static String proposalTagFromReasons(List<String> reasons) {
    for (final r in reasons) {
      const prefix = 'Candidate: ';
      if (r.startsWith(prefix)) return r.substring(prefix.length);
    }
    return 'unknown';
  }

  static AutoRigTrainingExample labelLayout({
    required String roomId,
    required String layoutId,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
    required String proposalTag,
    required String split,
  }) {
    final w = weights.normalized();
    final bounds = SimRoomBounds.fromGrid(gridCols: gridCols, gridRows: gridRows);
    final air =
        AirflowOptimizer.evaluate(furniture, bounds: bounds).circulationScore.clamp(0.0, 100.0);
    final light =
        LightingOptimizer.evaluate(furniture, bounds: bounds).exposureScore.clamp(0.0, 100.0);
    final ergo =
        ErgonomicsOptimizer.evaluate(furniture, bounds: bounds).comfortScore.clamp(0.0, 100.0);
    final space = SpatialAnalyzer.evaluate(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
    ).overallScore.clamp(0.0, 100.0);
    final overall = MultiObjectiveOptimizer.scoreLayout(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: w,
    );
    final validation = BenchmarkValidator.validateLayout(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      mode: 'overall',
    );
    final anchors = furniture
        .where(isAnchor)
        .map(AutoRigLayoutItem.fromFurniture)
        .toList(growable: false);
    final items =
        furniture.map(AutoRigLayoutItem.fromFurniture).toList(growable: false);
    return AutoRigTrainingExample(
      roomId: roomId,
      layoutId: layoutId,
      gridCols: gridCols,
      gridRows: gridRows,
      anchors: anchors,
      weights: w,
      items: items,
      airflow: air,
      lighting: light,
      ergonomics: ergo,
      spatial: space,
      overall: overall,
      collisionOk: !validation.hasHardLayoutConflicts,
      proposalTag: proposalTag,
      split: split,
    );
  }

  /// Auto-Rig proposals for one room + weight mix → labeled examples.
  static List<AutoRigTrainingExample> exportCandidates({
    required String roomId,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
    required String split,
  }) {
    final ranked = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    final out = <AutoRigTrainingExample>[];
    for (var i = 0; i < ranked.length; i++) {
      final r = ranked[i];
      final tag = proposalTagFromReasons(r.reasons);
      out.add(
        labelLayout(
          roomId: roomId,
          layoutId: '${roomId}__${tag}_$i',
          furniture: r.furniture,
          gridCols: gridCols,
          gridRows: gridRows,
          weights: weights,
          proposalTag: tag,
          split: split,
        ),
      );
    }
    return out;
  }

  /// Randomly jitter movable items to create hard negatives.
  static List<FurnitureItem> hardNegativeLayout({
    required List<FurnitureItem> baseline,
    required int gridCols,
    required int gridRows,
    required Random rng,
    int moves = 4,
  }) {
    final next = baseline.map((f) => f.copyWith()).toList();
    final movable = [
      for (var i = 0; i < next.length; i++)
        if (!isAnchor(next[i]) && !next[i].locked) i,
    ];
    if (movable.isEmpty) return next;

    for (var m = 0; m < moves; m++) {
      final idx = movable[rng.nextInt(movable.length)];
      final item = next[idx];
      final dx = rng.nextInt(5) - 2;
      final dy = rng.nextInt(5) - 2;
      final yaw = (item.yawDegrees + (rng.nextInt(4) * 90)) % 360.0;
      final x =
          (item.gridX + dx).clamp(0.0, max(0.0, gridCols - item.width)).toDouble();
      final y =
          (item.gridY + dy).clamp(0.0, max(0.0, gridRows - item.height)).toDouble();
      next[idx] = item.copyWith(gridX: x, gridY: y, yawDegrees: yaw);
    }
    return next;
  }

  static List<AutoRigTrainingExample> exportHardNegatives({
    required String roomId,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
    required String split,
    required Random rng,
    int count = 4,
  }) {
    final out = <AutoRigTrainingExample>[];
    for (var i = 0; i < count; i++) {
      final junk = hardNegativeLayout(
        baseline: furniture,
        gridCols: gridCols,
        gridRows: gridRows,
        rng: rng,
      );
      out.add(
        labelLayout(
          roomId: roomId,
          layoutId: '${roomId}__neg_$i',
          furniture: junk,
          gridCols: gridCols,
          gridRows: gridRows,
          weights: weights,
          proposalTag: 'hard_negative',
          split: split,
        ),
      );
    }
    return out;
  }

  /// All ordered pairs within a room where scores differ.
  static List<AutoRigPreferencePair> pairsFromExamples(
    List<AutoRigTrainingExample> examples,
  ) {
    final byRoom = <String, List<AutoRigTrainingExample>>{};
    for (final e in examples) {
      final key = '${e.roomId}|${e.weights.cacheKey}|${e.split}';
      (byRoom[key] ??= []).add(e);
    }
    final pairs = <AutoRigPreferencePair>[];
    for (final group in byRoom.values) {
      if (group.length < 2) continue;
      final w = group.first.weights;
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final a = group[i];
          final b = group[j];
          if ((a.overall - b.overall).abs() < 0.25) continue;
          final winner = a.overall >= b.overall ? a.layoutId : b.layoutId;
          pairs.add(
            AutoRigPreferencePair(
              roomId: a.roomId,
              weights: w,
              layoutAId: a.layoutId,
              layoutBId: b.layoutId,
              winnerId: winner,
              split: a.split,
            ),
          );
        }
      }
    }
    return pairs;
  }

  /// Clone a preset and optionally nudge size / opening placement.
  static ({
    List<FurnitureItem> furniture,
    int gridCols,
    int gridRows,
  }) sampleRoomVariant({
    required RoomData base,
    required Random rng,
  }) {
    var cols = base.gridCols + rng.nextInt(3) - 1;
    var rows = base.gridRows + rng.nextInt(3) - 1;
    cols = cols.clamp(5, 10);
    rows = rows.clamp(6, 12);

    final furniture = base.furniture.map((f) {
      final x = f.gridX.clamp(0.0, max(0.0, cols - f.width)).toDouble();
      final y = f.gridY.clamp(0.0, max(0.0, rows - f.height)).toDouble();
      return f.copyWith(gridX: x, gridY: y);
    }).toList();

    for (var i = 0; i < furniture.length; i++) {
      final f = furniture[i];
      if (f.iconName == 'door' && rng.nextBool()) {
        final y = (rng.nextDouble() * max(1.0, rows - f.height))
            .clamp(0.0, max(0.0, rows - f.height))
            .toDouble();
        furniture[i] = f.copyWith(gridX: 0, gridY: y);
      } else if (f.iconName == 'window' && rng.nextBool()) {
        final x = (rng.nextDouble() * max(1.0, cols - f.width))
            .clamp(0.0, max(0.0, cols - f.width))
            .toDouble();
        furniture[i] = f.copyWith(gridX: x, gridY: 0);
      }
    }

    return (furniture: furniture, gridCols: cols, gridRows: rows);
  }
}
