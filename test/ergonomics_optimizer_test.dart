import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/ergonomics_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/ergonomics_optimizer.dart';
import 'package:room_rig/services/ergonomics_simulator.dart';

void main() {
  group('ErgonomicsOptimizer', () {
    test('evaluate returns comfort metrics', () {
      final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
      final baseline = ErgonomicsPrototypeLayouts.baseline(source);
      final metrics = ErgonomicsOptimizer.evaluate(baseline);
      expect(metrics.comfortScore, inInclusiveRange(0, 100));
    });

    test('optimize improves comfort and clears chair pull-back', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = ErgonomicsPrototypeLayouts.baseline(room.furniture);
      final before = ErgonomicsOptimizer.evaluate(baseline);
      final result = ErgonomicsOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final chair = result.furniture.firstWhere((f) => f.id == 'chair');
      final desk = result.furniture.firstWhere((f) => f.id == 'desk');
      expect(chair.gridY, greaterThan(desk.gridY + desk.height * 0.5));
      expect(result.metrics.comfortScore, greaterThan(before.comfortScore));
      expect(result.metrics.chairClearance, greaterThan(before.chairClearance));
      expect(result.reasons, isNotEmpty);
    });

    test('optimize parks PC near the desk', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = ErgonomicsPrototypeLayouts.baseline(room.furniture);
      final result = ErgonomicsOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final desk = result.furniture.firstWhere((f) => f.id == 'desk');
      final pc = result.furniture.firstWhere((f) => f.id == 'pc');
      final dx = ((pc.gridX + pc.width * 0.5) - (desk.gridX + desk.width * 0.5)).abs();
      final dy = ((pc.gridY + pc.height * 0.5) - (desk.gridY + desk.height * 0.5)).abs();
      expect(dx + dy, lessThan(3.5), reason: 'PC should sit in desk reach envelope');
    });

    test('simulator builds frequent walk paths', () {
      final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
      final baseline = ErgonomicsPrototypeLayouts.baseline(source);
      final sim = ErgonomicsSimulator.build(furniture: baseline, optimized: false);
      expect(sim.paths, isNotEmpty);
      expect(sim.paths.any((p) => p.label.contains('Bed')), isTrue);
      expect(sim.reachCircle, isNotNull);
      expect(sim.metrics.pathScore, inInclusiveRange(0, 1));
    });
  });
}
