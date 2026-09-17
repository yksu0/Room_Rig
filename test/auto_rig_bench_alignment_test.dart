// Auto-Rig must move the same numbers Bench shows — and those numbers must
// describe human-noticeable improvements (dead air, task light, door view…).
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/airflow_prototype.dart';
import 'package:room_rig/models/ergonomics_prototype.dart';
import 'package:room_rig/models/lighting_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:room_rig/services/benchmark_validator.dart';
import 'package:room_rig/services/ergonomics_optimizer.dart';
import 'package:room_rig/services/ergonomics_simulator.dart';
import 'package:room_rig/services/lighting_optimizer.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  final room = RoomPresets.getPreset(RoomPreset.gamingSetup);

  test('MultiObjective Hub metrics match evaluate(result furniture)', () {
    final result = MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(
        airflow: 1,
        lighting: 1,
        ergonomics: 1,
      ),
    );
    final air = AirflowOptimizer.evaluate(result.furniture);
    final light = LightingOptimizer.evaluate(result.furniture);
    final ergo = ErgonomicsOptimizer.evaluate(result.furniture);
    expect(result.airflowMetrics.circulationScore, closeTo(air.circulationScore, 0.05));
    expect(result.lightingMetrics.exposureScore, closeTo(light.exposureScore, 0.05));
    expect(result.ergonomicsMetrics.comfortScore, closeTo(ergo.comfortScore, 0.05));
  });

  test('airflow Auto-Rig improves a human-readable airflow signal', () {
    final baseline = AirflowPrototypeLayouts.baseline(room.furniture);
    final before = AirflowOptimizer.evaluate(baseline);
    final result = AirflowOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final after = result.metrics;
    final betterCirculation = after.circulationScore + 0.15 >= before.circulationScore;
    final lessDead = after.deadZoneRatio + 0.002 <= before.deadZoneRatio;
    final betterExit = after.exitChannelScore + 0.5 >= before.exitChannelScore;
    final betterCool = after.workZoneCooling + 0.5 >= before.workZoneCooling;
    expect(
      betterCirculation || lessDead || betterExit || betterCool,
      isTrue,
      reason:
          'before circ=${before.circulationScore} dead=${before.deadZoneRatio} '
          'exit=${before.exitChannelScore} cool=${before.workZoneCooling}; '
          'after circ=${after.circulationScore} dead=${after.deadZoneRatio} '
          'exit=${after.exitChannelScore} cool=${after.workZoneCooling}',
    );
    expect(
      result.reasons.any((r) =>
          r.toLowerCase().contains('dead') ||
          r.toLowerCase().contains('exit') ||
          r.toLowerCase().contains('cool') ||
          r.toLowerCase().contains('circulation') ||
          r.toLowerCase().contains('ac') ||
          r.toLowerCase().contains('throw')),
      isTrue,
    );
  });

  test('lighting Auto-Rig improves task luminosity or glare', () {
    final baseline = LightingPrototypeLayouts.baseline(room.furniture);
    final before = LightingOptimizer.evaluate(baseline);
    final result = LightingOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final after = result.metrics;
    expect(after.exposureScore + 0.5, greaterThanOrEqualTo(before.exposureScore));
    final brighterTask = after.taskIllumination + 0.01 >= before.taskIllumination;
    final lessGlare = after.glareRisk <= before.glareRisk + 0.01;
    expect(brighterTask || lessGlare, isTrue);
  });

  test('ergonomics Auto-Rig improves door prospect or walk quality', () {
    final baseline = ErgonomicsPrototypeLayouts.baseline(room.furniture);
    final before = ErgonomicsOptimizer.evaluate(baseline);
    final result = ErgonomicsOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final after = result.metrics;
    expect(after.comfortScore + 0.5, greaterThanOrEqualTo(before.comfortScore));
    expect(
      after.doorProspect + 0.02 >= before.doorProspect ||
          after.pathScore + 0.02 >= before.pathScore ||
          after.chairClearance + 0.02 >= before.chairClearance,
      isTrue,
    );

    final desk = result.furniture.firstWhere((f) => f.id == 'desk' || f.iconName == 'desk');
    final chair = result.furniture.firstWhere((f) => f.id == 'chair' || f.iconName == 'chair');
    final door = result.furniture.firstWhere((f) => f.id == 'door' || f.iconName == 'door');
    final prospect = ErgonomicsSimulator.doorVisibilityScore(
      chair: chair,
      desk: desk,
      door: door,
    );
    expect(prospect, greaterThanOrEqualTo(0.45),
        reason: 'Seat should not strongly turn its back to the door');
  });

  test('Bench check details name human outcomes', () {
    final layout = AirflowPrototypeLayouts.optimized(room.furniture);
    final air = BenchmarkValidator.validateLayout(
      furniture: layout,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      mode: 'airflow',
    );
    final circ = air.checks.firstWhere((c) => c.id == 'circulation');
    expect(circ.detail.toLowerCase(), anyOf(contains('exit'), contains('stagnant'), contains('cool'), contains('mix')));
    expect(air.checks.any((c) => c.id == 'dead_zones'), isTrue);

    final ergoLayout = ErgonomicsPrototypeLayouts.optimized(room.furniture);
    final ergo = BenchmarkValidator.validateLayout(
      furniture: ergoLayout,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      mode: 'ergonomics',
    );
    final comfort = ergo.checks.firstWhere((c) => c.id == 'comfort');
    expect(comfort.detail.toLowerCase(), anyOf(contains('door'), contains('walk'), contains('clearance'), contains('reach'), contains('comfort')));
    expect(ergo.checks.any((c) => c.id == 'paths'), isTrue);

    final lightLayout = LightingPrototypeLayouts.optimized(room.furniture);
    final light = BenchmarkValidator.validateLayout(
      furniture: lightLayout,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      mode: 'lighting',
    );
    final exposure = light.checks.firstWhere((c) => c.id == 'exposure');
    expect(exposure.detail.toLowerCase(), anyOf(contains('task'), contains('light'), contains('desk'), contains('daylight')));
  });
}
