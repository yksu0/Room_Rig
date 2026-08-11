import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/airflow_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';

void main() {
  group('AirflowOptimizer', () {
    test('evaluate returns circulation metrics for a layout', () {
      final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
      final baseline = AirflowPrototypeLayouts.baseline(source);
      final metrics = AirflowOptimizer.evaluate(baseline);
      expect(metrics.circulationScore, inInclusiveRange(0, 100));
      expect(metrics.fluidVoxelCount, greaterThan(0));
    });

    test('optimize moves AC off the corner and improves circulation', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = AirflowPrototypeLayouts.baseline(room.furniture);
      final before = AirflowOptimizer.evaluate(baseline);

      final result = AirflowOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );

      final ac = result.furniture.firstWhere((f) => f.id == 'ac');
      expect(ac.gridY, lessThan(5.5), reason: 'AC should leave the far corner');
      expect(result.reasons, isNotEmpty);
      expect(result.metrics.circulationScore, greaterThanOrEqualTo(before.circulationScore - 1));
      // Optimized should generally beat a cornered-AC baseline.
      expect(result.metrics.circulationScore, greaterThan(before.circulationScore));
    });

    test('optimize parks fan on the wall, not mid-room', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = AirflowPrototypeLayouts.baseline(room.furniture);
      final result = AirflowOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final fan = result.furniture.firstWhere((f) => f.id == 'fan');
      expect(fan.gridX, lessThan(1.0), reason: 'Fan should stay against the desk wall');
    });
  });
}
