import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/layout_optimizer_common.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  test('mountDeskTopItems parks monitor and PC on the desk', () {
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 1,
        gridY: 2,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 4,
        gridY: 5,
      ),
      FurnitureItem(
        id: 'pc',
        name: 'PC Tower',
        iconName: 'pc',
        category: 'airflow',
        gridX: 0,
        gridY: 6,
      ),
    ];

    final mounted = LayoutOptimizerCommon.mountDeskTopItems(furniture);
    final desk = mounted.firstWhere((f) => f.id == 'desk');
    final monitor = mounted.firstWhere((f) => f.id == 'monitor');
    final pc = mounted.firstWhere((f) => f.id == 'pc');

    expect(SurfaceMounts.hostUnder(monitor, mounted)?.id, desk.id);
    expect(SurfaceMounts.hostUnder(pc, mounted)?.id, desk.id);
  });

  test('planWorkCluster centers chair on desk with pull-back', () {
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        gridX: 0,
        gridY: 0,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'chair',
        name: 'Chair',
        iconName: 'chair',
        category: 'ergonomics',
        gridX: 5,
        gridY: 6,
      ),
      FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 0,
        gridY: 6,
      ),
    ];
    final targets = <String, ({double x, double y})>{};
    final reasons = LayoutOptimizerCommon.planWorkCluster(
      furniture: furniture,
      targets: targets,
      gridCols: 6,
      gridRows: 8,
      bias: WorkClusterBias.ergonomics,
    );

    expect(targets['desk'], isNotNull);
    expect(targets['chair'], isNotNull);
    expect(targets['monitor'], isNotNull);
    final desk = targets['desk']!;
    final chair = targets['chair']!;
    expect(chair.y, greaterThan(desk.y + 0.8));
    expect((chair.x - desk.x).abs(), lessThan(1.2));
    expect(reasons, isNotEmpty);
  });

  test('Auto-Rig keeps desk-top gear on the desk after optimize', () {
    final room = RoomPresets.getPreset(RoomPreset.homeOffice);
    final baseline = room.furniture.map((f) {
      if (SurfaceMounts.isDeskTopItem(f)) {
        return f.copyWith(gridX: 0, gridY: 6);
      }
      return f.copyWith();
    }).toList();

    final result = MultiObjectiveOptimizer.optimize(
      furniture: baseline,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: const MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7),
    );

    final desk = result.furniture.where(SurfaceMounts.isDeskHost).first;
    for (final item in result.furniture.where(SurfaceMounts.isDeskTopItem)) {
      expect(
        SurfaceMounts.hostUnder(item, result.furniture)?.id,
        desk.id,
        reason: '${item.id} should sit on the desk after Auto-Rig',
      );
    }
  });
}
