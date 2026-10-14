import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/autorug_training_export.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  test('exportCandidates labels Auto-Rig proposals with schema fields', () {
    final room = RoomPresets.getPreset(RoomPreset.homeOffice);
    final examples = AutoRigTrainingExport.exportCandidates(
      roomId: 'test_office',
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(
        airflow: 1,
        lighting: 1,
        ergonomics: 1,
        spatial: 0,
      ),
      split: 'train',
    );

    expect(examples, isNotEmpty);
    final json = examples.first.toJson();
    expect(json['room_id'], 'test_office');
    expect(json['layout_id'], isNotEmpty);
    expect(json['weights'], containsPair('airflow', isA<double>()));
    expect(json['layout']['items'], isNotEmpty);
    expect(json['labels']['overall'], inInclusiveRange(0, 100));
    expect(json['labels']['proposal_tag'], isNotEmpty);
    expect(json['anchors'], isNotEmpty);
  });

  test('pairsFromExamples pick higher overall as winner', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final rng = Random(1);
    final examples = <AutoRigTrainingExample>[
      ...AutoRigTrainingExport.exportCandidates(
        roomId: 'g0',
        furniture: room.furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: AutoRigTrainingExport.weightMixes.first,
        split: 'train',
      ),
      ...AutoRigTrainingExport.exportHardNegatives(
        roomId: 'g0',
        furniture: room.furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: AutoRigTrainingExport.weightMixes.first,
        split: 'train',
        rng: rng,
        count: 2,
      ),
    ];
    final byId = {for (final e in examples) e.layoutId: e};
    final pairs = AutoRigTrainingExport.pairsFromExamples(examples);
    expect(pairs, isNotEmpty);
    for (final p in pairs.take(20)) {
      final a = byId[p.layoutAId]!;
      final b = byId[p.layoutBId]!;
      final winner = byId[p.winnerId]!;
      expect(winner.overall, greaterThanOrEqualTo(a.overall));
      expect(winner.overall, greaterThanOrEqualTo(b.overall));
    }
  });
}
