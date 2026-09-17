import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MultiObjectiveWeights normalizes and reports dominant goal', () {
    const w = MultiObjectiveWeights(airflow: 0.95, lighting: 0.2, ergonomics: 0.2);
    expect(w.airflowNorm + w.lightingNorm + w.ergonomicsNorm, closeTo(1.0, 0.001));
    expect(w.dominantGoal, 'airflow');
    expect(w.summaryLabel.contains('Air'), isTrue);

    const balanced = MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7);
    expect(balanced.dominantGoal, isNull);
  });

  test('MultiObjectiveOptimizer blends without sequential overwrite', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final baseline = room.furniture.map((f) => f.copyWith()).toList();

    final result = MultiObjectiveOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7),
    );

    expect(result.furniture.length, baseline.length);
    expect(result.reasons.first.contains('Weight mix'), isTrue);
    expect(result.reasons.any((r) => r.contains('Blended')), isTrue);
    expect(result.airflowMetrics.circulationScore, greaterThanOrEqualTo(0));
    expect(result.lightingMetrics.exposureScore, greaterThanOrEqualTo(0));
    expect(result.ergonomicsMetrics.comfortScore, greaterThanOrEqualTo(0));
  });

  test('AppState.runOptimization respects live weight mix for balanced', () {
    final state = AppState();
    state.setOptimizeWeights(airflow: 0.6, lighting: 0.8, ergonomics: 0.5);
    final before = state.furniture.map((f) => '${f.id}:${f.gridX},${f.gridY}').toList();

    state.runOptimization(); // no goal preset — uses live sliders

    expect(state.isOptimized, isTrue);
    expect(state.lastOptimizeReasons, isNotEmpty);
    expect(state.optimizeWeights.summaryLabel.contains('Light'), isTrue);
    final after = state.furniture.map((f) => '${f.id}:${f.gridX},${f.gridY}').toList();
    expect(after == before, isFalse);
  });
}
