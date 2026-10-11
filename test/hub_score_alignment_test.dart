import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/room_scale.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:room_rig/services/comfort_heuristics.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clearances share one cell→meter scale', () {
    expect(RoomScale.cellMeters, 0.6);
    expect(ComfortHeuristics.chairPullbackCells, 0.95);
    expect(
      ComfortHeuristics.chairPullbackMeters,
      closeTo(0.95 * 0.6, 1e-9),
    );
    expect(
      ComfortHeuristics.minAisleCells,
      closeTo(0.9 / 0.6, 1e-9),
    );
    expect(
      ComfortHeuristics.doorApproachDepthMeters,
      closeTo(1.2 * 0.6, 1e-9),
    );
  });

  test('Hub overallScore matches Auto-Rig scoreLayout composite', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.acceptPresetAsReady();

    final expected = MultiObjectiveOptimizer.scoreLayout(
      furniture: state.committedFurniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      weights: state.optimizeWeights,
    );
    expect(state.overallScore, closeTo(expected, 1e-6));
  });

  test('ROUGH Hub rings use geometry scores, not catalog impact tags', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.acceptPresetAsReady();

    final movable = state.furniture.firstWhere(
      (f) =>
          f.iconName != 'door' &&
          f.iconName != 'window' &&
          f.iconName != 'ac',
    );
    state.moveFurniture(movable.id, movable.gridX + 0.5, movable.gridY);
    expect(state.scoresAreSimulated, isTrue);

    final sim = AirflowOptimizer.evaluate(state.committedFurniture).circulationScore;
    expect(state.airflowScore, closeTo(sim, 0.01));

    final expected = MultiObjectiveOptimizer.scoreLayout(
      furniture: state.committedFurniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      weights: state.optimizeWeights,
    );
    expect(state.overallScore, closeTo(expected, 1e-6));
  });
}
