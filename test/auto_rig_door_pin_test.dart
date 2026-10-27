import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/airflow_optimizer.dart';
import 'package:room_rig/services/benchmark_layouts.dart';
import 'package:room_rig/services/layout_optimizer_common.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  final room = RoomPresets.getPreset(RoomPreset.gamingSetup);

  FurnitureItem? doorOf(List<FurnitureItem> items) =>
      LayoutOptimizerCommon.findDoor(items);

  test('applyTargets does not move structural mounts even if targeted', () {
    final door = doorOf(room.furniture);
    expect(door, isNotNull);
    final before = door!;
    final next = LayoutOptimizerCommon.applyTargets(
      source: room.furniture,
      targets: {before.id: (x: 0.0, y: (room.gridRows - 1.8).clamp(4.0, room.gridRows - 1.0))},
      cols: room.gridCols.toDouble(),
      rows: room.gridRows.toDouble(),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final after = doorOf(next)!;
    expect(after.gridX, before.gridX);
    expect(after.gridY, before.gridY);
    expect(after.yawDegrees, before.yawDegrees);
  });

  test('Auto-Rig / Benchmark Improved keep door pose identical', () {
    final door = doorOf(room.furniture)!;
    expect(SurfaceMounts.isStructuralMount(door), isTrue);

    final multi = MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(
        airflow: 1,
        lighting: 1,
        ergonomics: 1,
      ),
    );
    final multiDoor = doorOf(multi.furniture)!;
    expect(multiDoor.gridX, door.gridX);
    expect(multiDoor.gridY, door.gridY);
    expect(multiDoor.yawDegrees, door.yawDegrees);

    final air = AirflowOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final airDoor = doorOf(air.furniture)!;
    expect(airDoor.gridX, door.gridX);
    expect(airDoor.gridY, door.gridY);

    final layouts = BenchmarkLayoutBuilder.build(
      mode: BenchmarkMode.airflow,
      roomFurniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final improvedDoor = doorOf(layouts.improved)!;
    expect(improvedDoor.gridX, door.gridX);
    expect(improvedDoor.gridY, door.gridY);
    expect(improvedDoor.yawDegrees, door.yawDegrees);
  });
}
