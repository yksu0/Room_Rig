// ignore_for_file: avoid_print
//
// A/B: pipeline sort vs AutoRigRanker on the same Auto-Rig proposals.
// Hub overall always comes from MultiObjectiveOptimizer.scoreLayout.
//
//   flutter test tool/compare_autorug_sort.dart
//   flutter test tool/compare_autorug_sort.dart --dart-define=AUTORUG_ROOMS=24

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/autorug_ranker.dart';
import 'package:room_rig/services/autorug_training_export.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compare pipeline vs AI Auto-Rig sort', () async {
    final roomsDefine =
        const String.fromEnvironment('AUTORUG_ROOMS', defaultValue: '');
    final rooms = int.tryParse(roomsDefine) ?? 24;
    final seed = int.tryParse(
          const String.fromEnvironment('AUTORUG_SEED', defaultValue: ''),
        ) ??
        42;
    final outDir = const String.fromEnvironment(
      'AUTORUG_COMPARE_OUT',
      defaultValue: 'ml/runs/autorug_compare',
    );

    await AutoRigRanker.load();
    expect(AutoRigRanker.isLoaded, isTrue);

    final rng = Random(seed);
    final presets = RoomPreset.values;
    final mixes = AutoRigTrainingExport.weightMixes;

    var agreeTop1 = 0;
    var total = 0;
    final regrets = <double>[];
    final pipelineScores = <double>[];
    final aiScores = <double>[];
    final rows = <Map<String, dynamic>>[];

    for (var r = 0; r < rooms; r++) {
      final preset = presets[r % presets.length];
      final base = RoomPresets.getPreset(preset);
      final variant = AutoRigTrainingExport.sampleRoomVariant(
        base: base,
        rng: rng,
      );
      final weights = mixes[r % mixes.length];
      final roomId = '${preset.name}_r${r.toString().padLeft(4, '0')}';

      final pipeline = MultiObjectiveOptimizer.optimizeCandidates(
        furniture: variant.furniture,
        gridCols: variant.gridCols,
        gridRows: variant.gridRows,
        weights: weights,
        useAiSort: false,
      );
      final ai = MultiObjectiveOptimizer.optimizeCandidates(
        furniture: variant.furniture,
        gridCols: variant.gridCols,
        gridRows: variant.gridRows,
        weights: weights,
        useAiSort: true,
      );
      if (pipeline.isEmpty || ai.isEmpty) continue;

      final pBest = pipeline.first;
      final aBest = ai.first;
      final same = _sameLayout(pBest.furniture, aBest.furniture);
      if (same) agreeTop1++;
      total++;

      pipelineScores.add(pBest.score);
      aiScores.add(aBest.score);
      final regret = pBest.score - aBest.score;
      regrets.add(regret);

      rows.add({
        'room_id': roomId,
        'weights': weights.summaryLabel,
        'pipeline_score': double.parse(pBest.score.toStringAsFixed(2)),
        'ai_score': double.parse(aBest.score.toStringAsFixed(2)),
        'regret': double.parse(regret.toStringAsFixed(2)),
        'agree_top1': same,
        'pipeline_rank_label': pBest.rankLabel,
        'ai_rank_label': aBest.rankLabel,
        'candidate_count': pipeline.length,
      });
    }

    expect(total, greaterThan(0));

    final meanPipe = _mean(pipelineScores);
    final meanAi = _mean(aiScores);
    final meanRegret = _mean(regrets);
    final agreeRate = agreeTop1 / total;
    final within2 = regrets.where((r) => r.abs() <= 2.0).length / total;
    final aiWins = regrets.where((r) => r < -0.25).length;
    final pipeWins = regrets.where((r) => r > 0.25).length;
    final ties = total - aiWins - pipeWins;

    final summary = {
      'rooms': total,
      'seed': seed,
      'agree_top1': double.parse(agreeRate.toStringAsFixed(3)),
      'mean_pipeline_hub': double.parse(meanPipe.toStringAsFixed(2)),
      'mean_ai_hub': double.parse(meanAi.toStringAsFixed(2)),
      'mean_regret_pipeline_minus_ai':
          double.parse(meanRegret.toStringAsFixed(2)),
      'within_2_hub_points': double.parse(within2.toStringAsFixed(3)),
      'pipeline_better_count': pipeWins,
      'ai_better_count': aiWins,
      'near_tie_count': ties,
    };

    final dir = Directory(outDir)..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
    File('${dir.path}${Platform.pathSeparator}rows.jsonl').writeAsStringSync(
      '${rows.map(jsonEncode).join('\n')}\n',
    );

    print('=== Auto-Rig pipeline vs AI sort ===');
    print(const JsonEncoder.withIndent('  ').convert(summary));
    print('Wrote ${dir.path}');

    // Soft expectations: AI should not crater Hub scores on average.
    expect(meanRegret, lessThan(5.0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

bool _sameLayout(List<FurnitureItem> a, List<FurnitureItem> b) {
  if (a.length != b.length) return false;
  final byId = {for (final f in b) f.id: f};
  for (final fa in a) {
    final fb = byId[fa.id];
    if (fb == null) return false;
    if ((fa.gridX - fb.gridX).abs() > 0.05) return false;
    if ((fa.gridY - fb.gridY).abs() > 0.05) return false;
    if ((fa.yawDegrees - fb.yawDegrees).abs() > 0.5) return false;
  }
  return true;
}

double _mean(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  return xs.reduce((a, b) => a + b) / xs.length;
}
