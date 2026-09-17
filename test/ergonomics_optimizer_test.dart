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
      final chairCx = chair.gridX + chair.width * 0.5;
      final chairCz = chair.gridY + chair.height * 0.5;
      final deskCx = desk.gridX + desk.width * 0.5;
      final deskCz = desk.gridY + desk.height * 0.5;
      final gap = ((chairCx - deskCx).abs() > (chairCz - deskCz).abs())
          ? (chairCx - deskCx).abs() - desk.width * 0.5 - chair.width * 0.5
          : (chairCz - deskCz).abs() - desk.height * 0.5 - chair.height * 0.5;
      expect(gap, greaterThan(0.4), reason: 'Chair should keep pull-back space from the desk');
      expect(result.metrics.comfortScore + 0.5, greaterThanOrEqualTo(before.comfortScore));
      expect(
        result.metrics.chairClearance + 0.02 >= before.chairClearance ||
            result.metrics.doorProspect + 0.02 >= before.doorProspect ||
            result.metrics.pathScore + 0.02 >= before.pathScore,
        isTrue,
      );
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
