import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/autorug_ranker.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ridge asset loads and feature dim matches coef', () async {
    final raw =
        await rootBundle.loadString('assets/models/autorug_rank_ridge.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final ranker = AutoRigRanker.fromJson(json);
    expect(ranker.coef.length, AutoRigRanker.featureDimFor(ranker.slots));

    final room = RoomPresets.getPreset(RoomPreset.homeOffice);
    const weights = MultiObjectiveWeights(
      airflow: 1,
      lighting: 1,
      ergonomics: 1,
      spatial: 0,
    );
    final feats = ranker.features(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    expect(feats.length, ranker.coef.length);
    final score = ranker.score(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    expect(score.isFinite, isTrue);
  });

  test('useAiSort ranks by ridge score when ranker is loaded', () async {
    await AutoRigRanker.load();
    expect(AutoRigRanker.isLoaded, isTrue);
    final ranker = AutoRigRanker.instance!;

    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    const weights = MultiObjectiveWeights(
      airflow: 0.4,
      lighting: 0.2,
      ergonomics: 0.3,
      spatial: 0.1,
    );

    final ai = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
      useAiSort: true,
    );
    expect(ai, isNotEmpty);

    if (ai.length >= 2) {
      final s0 = ranker.score(
        furniture: ai[0].furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: weights,
      );
      final s1 = ranker.score(
        furniture: ai[1].furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: weights,
      );
      expect(s0, greaterThanOrEqualTo(s1));
    }

    AutoRigRanker.enabled = false;
  });
}
