import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/bench_layouts.dart';
import 'package:room_rig/services/layout_optimizer_common.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  const weights = MultiObjectiveWeights(
    airflow: 0.7,
    lighting: 0.7,
    ergonomics: 0.7,
  );

  List<FurnitureItem> gamingFurniture() =>
      RoomPresets.getPreset(RoomPreset.gamingSetup)
          .furniture
          .map((f) => f.copyWith())
          .toList();

  test('optimizeCandidates ranks best score first and is stable', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final baseline = gamingFurniture();

    final a = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final b = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );

    expect(a, isNotEmpty);
    expect(a.first.rank, 1);
    expect(a.first.rankLabel, contains('Best of'));
    for (var i = 1; i < a.length; i++) {
      expect(a[i].score, lessThanOrEqualTo(a[i - 1].score));
    }

    expect(
      BenchLayoutBuilder.fingerprintOf(a.first.furniture),
      BenchLayoutBuilder.fingerprintOf(b.first.furniture),
    );
    expect(a.first.score, closeTo(b.first.score, 0.01));
  });

  test('optimize returns the top-ranked candidate', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final baseline = gamingFurniture();
    final ranked = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final best = MultiObjectiveOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    expect(
      BenchLayoutBuilder.fingerprintOf(best.furniture),
      BenchLayoutBuilder.fingerprintOf(ranked.first.furniture),
    );
  });

  test('ranked pool has diverse fingerprints when multiple candidates exist', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final ranked = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: gamingFurniture(),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    expect(ranked.length, greaterThanOrEqualTo(2));
    final fps = ranked.map((r) => BenchLayoutBuilder.fingerprintOf(r.furniture)).toSet();
    expect(fps.length, ranked.length);
  });

  test('best-of search keeps monitor and PC on the same work desk', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final result = MultiObjectiveOptimizer.optimize(
      furniture: gamingFurniture(),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final desk = LayoutOptimizerCommon.findDesk(result.furniture);
    expect(desk, isNotNull);
    final monitor = result.furniture.where((f) => f.iconName == 'monitor');
    final pcs = result.furniture.where((f) => f.iconName == 'pc');
    for (final m in monitor) {
      expect(SurfaceMounts.hostUnder(m, result.furniture)?.id, desk!.id);
    }
    for (final pc in pcs) {
      expect(SurfaceMounts.hostUnder(pc, result.furniture)?.id, desk!.id);
    }
  });
}
