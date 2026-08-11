import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/airflow_prototype.dart';
import 'package:room_rig/models/ergonomics_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/benchmark_validator.dart';

void main() {
  group('BenchmarkValidator', () {
    test('fails empty layouts', () {
      final result = BenchmarkValidator.validateLayout(
        furniture: const [],
        gridCols: 6,
        gridRows: 8,
      );
      expect(result.passed, isFalse);
      expect(result.checks.any((c) => c.id == 'empty'), isTrue);
    });

    test('validates airflow geometry against live layout', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final baseline = AirflowPrototypeLayouts.baseline(room.furniture);
      final optimized = AirflowPrototypeLayouts.optimized(room.furniture);

      final before = BenchmarkValidator.validateLayout(
        furniture: baseline,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        mode: 'airflow',
      );
      final after = BenchmarkValidator.validateLayout(
        furniture: optimized,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        mode: 'airflow',
      );

      expect(before.checks, isNotEmpty);
      expect(after.score, greaterThanOrEqualTo(before.score - 1));
      expect(after.checks.any((c) => c.id == 'circulation'), isTrue);
      expect(after.checks.any((c) => c.id == 'conflicts'), isTrue);
    });

    test('ergonomics path check exists', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final layout = ErgonomicsPrototypeLayouts.optimized(room.furniture);
      final result = BenchmarkValidator.validateLayout(
        furniture: layout,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        mode: 'ergonomics',
      );
      expect(result.checks.any((c) => c.id == 'paths'), isTrue);
      expect(result.checks.any((c) => c.id == 'comfort'), isTrue);
    });
  });
}
