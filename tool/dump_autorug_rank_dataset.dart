// ignore_for_file: avoid_print
//
// Dump Auto-Rig ranker training JSONL (layouts + pairwise preferences).
// Must run under Flutter (simulators pull Flutter widgets):
//
//   flutter test tool/dump_autorug_rank_dataset.dart
//   flutter test tool/dump_autorug_rank_dataset.dart --dart-define=AUTORUG_SMOKE=1
//   flutter test tool/dump_autorug_rank_dataset.dart --dart-define=AUTORUG_ROOMS=80 --dart-define=AUTORUG_OUT=ml/datasets/autorug_rank

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/autorug_training_export.dart';

void main() {
  test('dump Auto-Rig rank dataset', () {
    // dart-define booleans must be the literal "true" (not "1").
    final smokeDefine =
        const String.fromEnvironment('AUTORUG_SMOKE', defaultValue: '');
    final smoke = smokeDefine == 'true' || smokeDefine == '1';
    final roomsDefine =
        const String.fromEnvironment('AUTORUG_ROOMS', defaultValue: '');
    final rooms = roomsDefine.isEmpty
        ? (smoke ? 4 : 24)
        : (int.tryParse(roomsDefine) ?? (smoke ? 4 : 24));
    final seedDefine =
        const String.fromEnvironment('AUTORUG_SEED', defaultValue: '');
    final seed = int.tryParse(seedDefine) ?? 42;
    final negDefine =
        const String.fromEnvironment('AUTORUG_NEGATIVES', defaultValue: '');
    final negativesPerMix = negDefine.isEmpty
        ? (smoke ? 2 : 3)
        : (int.tryParse(negDefine) ?? (smoke ? 2 : 3));
    final outDir = const String.fromEnvironment(
      'AUTORUG_OUT',
      defaultValue: 'ml/datasets/autorug_rank',
    );

    final rng = Random(seed);
    final presets = RoomPreset.values;
    final examples = <AutoRigTrainingExample>[];

    for (var r = 0; r < rooms; r++) {
      final preset = presets[r % presets.length];
      final base = RoomPresets.getPreset(preset);
      final variant = AutoRigTrainingExport.sampleRoomVariant(
        base: base,
        rng: rng,
      );
      final roomId = '${preset.name}_r${r.toString().padLeft(4, '0')}_s$seed';
      final split = (r % 5 == 4 || preset == RoomPreset.minimalistBedroom)
          ? 'val'
          : 'train';

      final mixes = smoke
          ? [AutoRigTrainingExport.weightMixes.first]
          : AutoRigTrainingExport.weightMixes;

      for (var mi = 0; mi < mixes.length; mi++) {
        final weights = mixes[mi];
        final mixRoomId = mixes.length == 1 ? roomId : '${roomId}_w$mi';
        examples.addAll(
          AutoRigTrainingExport.exportCandidates(
            roomId: mixRoomId,
            furniture: variant.furniture,
            gridCols: variant.gridCols,
            gridRows: variant.gridRows,
            weights: weights,
            split: split,
          ),
        );
        examples.addAll(
          AutoRigTrainingExport.exportHardNegatives(
            roomId: mixRoomId,
            furniture: variant.furniture,
            gridCols: variant.gridCols,
            gridRows: variant.gridRows,
            weights: weights,
            split: split,
            rng: rng,
            count: negativesPerMix,
          ),
        );
      }
    }

    final pairs = AutoRigTrainingExport.pairsFromExamples(examples);
    final dir = Directory(outDir);
    dir.createSync(recursive: true);

    final layoutsPath = '${dir.path}${Platform.pathSeparator}layouts.jsonl';
    final pairsPath = '${dir.path}${Platform.pathSeparator}pairs.jsonl';
    final metaPath = '${dir.path}${Platform.pathSeparator}meta.json';

    File(layoutsPath).writeAsStringSync(
      examples.map((e) => jsonEncode(e.toJson())).join('\n') +
          (examples.isEmpty ? '' : '\n'),
    );
    File(pairsPath).writeAsStringSync(
      pairs.map((p) => jsonEncode(p.toJson())).join('\n') +
          (pairs.isEmpty ? '' : '\n'),
    );

    final trainN = examples.where((e) => e.split == 'train').length;
    final valN = examples.where((e) => e.split == 'val').length;
    File(metaPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'seed': seed,
        'rooms': rooms,
        'layouts': examples.length,
        'pairs': pairs.length,
        'train_layouts': trainN,
        'val_layouts': valN,
        'negatives_per_mix': negativesPerMix,
        'smoke': smoke,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    print('Wrote $layoutsPath (${examples.length} layouts)');
    print('Wrote $pairsPath (${pairs.length} pairs)');
    print('Wrote $metaPath (train=$trainN val=$valN)');
    expect(examples, isNotEmpty);
    expect(pairs, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
