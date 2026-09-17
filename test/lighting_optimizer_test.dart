import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/lighting_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/lighting_optimizer.dart';

void main() {
  group('LightingOptimizer', () {
    test('evaluate returns exposure metrics', () {
      final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
      final baseline = LightingPrototypeLayouts.baseline(source);
      final metrics = LightingOptimizer.evaluate(baseline);
      expect(metrics.exposureScore, inInclusiveRange(0, 100));
    });

    test('optimize moves desk toward daylight and improves exposure', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = LightingPrototypeLayouts.baseline(room.furniture);
      final before = LightingOptimizer.evaluate(baseline);
      final result = LightingOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final desk = result.furniture.firstWhere((f) => f.id == 'desk');
      expect(desk.gridY, lessThan(4.0), reason: 'Desk should move into daylight band');
      expect(result.metrics.exposureScore, greaterThan(before.exposureScore));
      expect(result.reasons, isNotEmpty);
    });

    test('optimize places lamp near the desk', () {
      final room = RoomPresets.getPreset(RoomPreset.homeOffice);
      final baseline = LightingPrototypeLayouts.baseline(room.furniture);
      final result = LightingOptimizer.optimize(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final desk = result.furniture.firstWhere((f) => f.id == 'desk');
      final lamp = result.furniture.firstWhere((f) => f.id == 'lamp');
      final dx = (lamp.gridX - desk.gridX).abs();
      final dy = (lamp.gridY - desk.gridY).abs();
      expect(dx + dy, lessThan(3.5), reason: 'Lamp should sit near the desk');
    });
  });
}
