// On-device Auto-Rig layout scorer (ridge weights distilled from simulators).
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../models/room_model.dart';
import 'benchmark_validator.dart';
import 'multi_objective_optimizer.dart';

/// Feature slots must match `ml/autorug_rank/train_ranker.py` `_SLOTS`.
const autorugRankSlots = <String>[
  'desk',
  'chair',
  'bed',
  'lamp',
  'fan',
  'ac',
  'shelf',
  'sofa',
  'pc',
  'monitor',
  'table',
  'plant',
  'door',
  'window',
  'other',
];

class AutoRigRanker {
  AutoRigRanker._({
    required this.coef,
    required this.intercept,
    required this.slots,
  });

  final List<double> coef;
  final double intercept;
  final List<String> slots;

  static AutoRigRanker? _instance;
  static bool get isLoaded => _instance != null;
  static AutoRigRanker? get instance => _instance;

  /// Global enable for Auto-Rig AI sort (off by default).
  static bool enabled = false;

  static const assetPath = 'assets/models/autorug_rank_ridge.json';

  static Future<AutoRigRanker> load({String path = assetPath}) async {
    final raw = await rootBundle.loadString(path);
    final ranker = fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _instance = ranker;
    return ranker;
  }

  static AutoRigRanker fromJson(Map<String, dynamic> json) {
    final coef = (json['coef'] as List).map((e) => (e as num).toDouble()).toList();
    final intercept = (json['intercept'] as num).toDouble();
    final slots = (json['slots'] as List?)?.cast<String>() ?? autorugRankSlots;
    if (coef.length != featureDimFor(slots)) {
      throw StateError(
        'AutoRigRanker coef length ${coef.length} != expected ${featureDimFor(slots)}',
      );
    }
    return AutoRigRanker._(coef: coef, intercept: intercept, slots: slots);
  }

  static int featureDimFor(List<String> slots) =>
      8 + slots.length * 6 + 8 * 3 + 2;

  /// Predicted overall-style score (higher is better). Cheap; no CFD.
  double score({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final x = features(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    if (x.length != coef.length) {
      throw StateError('feature dim ${x.length} != coef ${coef.length}');
    }
    var s = intercept;
    for (var i = 0; i < coef.length; i++) {
      s += coef[i] * x[i];
    }
    return s;
  }

  List<double> features({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
  }) {
    final cols = max(1.0, gridCols.toDouble());
    final rows = max(1.0, gridRows.toDouble());
    final diag = sqrt(cols * cols + rows * rows);
    final w = weights.normalized();
    final bySlot = <String, List<FurnitureItem>>{
      for (final s in slots) s: <FurnitureItem>[],
    };
    for (final item in furniture) {
      bySlot[_slotFor(item)]!.add(item);
    }

    final collisionOk = !BenchmarkValidator.validateLayout(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      mode: 'overall',
    ).hasHardLayoutConflicts;

    final feats = <double>[
      w.airflowNorm,
      w.lightingNorm,
      w.ergonomicsNorm,
      w.spatialNorm,
      cols / 12.0,
      rows / 12.0,
      collisionOk ? 1.0 : 0.0,
      furniture.length / 20.0,
    ];

    final centers = <String, (double, double)>{};
    for (final s in slots) {
      final items = bySlot[s]!;
      if (items.isEmpty) {
        feats.addAll(const [0, 0, 0, 0, 0, 0]);
        continue;
      }
      final meanX =
          items.map((i) => i.gridX).reduce((a, b) => a + b) / items.length;
      final meanY =
          items.map((i) => i.gridY).reduce((a, b) => a + b) / items.length;
      final meanYaw = items.map((i) => i.yawDegrees).reduce((a, b) => a + b) /
          items.length;
      final meanArea = items
              .map((i) => i.width * i.height)
              .reduce((a, b) => a + b) /
          items.length /
          (cols * rows);
      final yaw = meanYaw * pi / 180.0;
      final first = items.first;
      centers[s] = (
        (first.gridX + first.width * 0.5) / cols,
        (first.gridY + first.height * 0.5) / rows,
      );
      feats.addAll([
        1.0,
        meanX / cols,
        meanY / rows,
        sin(yaw),
        cos(yaw),
        meanArea,
      ]);
    }

    List<double> rel(String a, String b) {
      final ca = centers[a];
      final cb = centers[b];
      if (ca == null || cb == null) return const [0, 0, 0];
      final dx = ca.$1 - cb.$1;
      final dy = ca.$2 - cb.$2;
      final dist = sqrt(dx * cols * dx * cols + dy * rows * dy * rows) / diag;
      return [dist, dx, dy];
    }

    feats.addAll(rel('desk', 'chair'));
    feats.addAll(rel('desk', 'window'));
    feats.addAll(rel('desk', 'door'));
    feats.addAll(rel('chair', 'door'));
    feats.addAll(rel('bed', 'door'));
    feats.addAll(rel('fan', 'ac'));
    feats.addAll(rel('lamp', 'desk'));
    feats.addAll(rel('monitor', 'desk'));

    final desks = bySlot['desk']!;
    final chairs = bySlot['chair']!;
    final windows = bySlot['window']!;
    if (desks.isNotEmpty && chairs.isNotEmpty) {
      final dYaw = desks.first.yawDegrees;
      final cYaw = chairs.first.yawDegrees;
      var delta = (cYaw - dYaw + 180) % 360 - 180;
      feats.add(delta.abs() / 180.0);
    } else {
      feats.add(0);
    }
    if (desks.isNotEmpty && windows.isNotEmpty) {
      final dYaw = desks.first.yawDegrees % 360.0;
      final squareOn = min((dYaw - 0.0).abs(), (dYaw - 180.0).abs()) / 180.0;
      feats.add(squareOn);
    } else {
      feats.add(0);
    }

    return feats;
  }

  String _slotFor(FurnitureItem item) {
    final key = item.iconName.toLowerCase();
    for (final s in slots) {
      if (s == 'other') continue;
      if (key.contains(s)) return s;
    }
    final id = item.id.toLowerCase();
    for (final s in slots) {
      if (s == 'other') continue;
      if (id.contains(s)) return s;
    }
    return 'other';
  }
}
