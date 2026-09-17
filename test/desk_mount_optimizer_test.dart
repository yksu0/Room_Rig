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

  test('monitor and PC stay on the work desk even when overlapping a lounge table', () {
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
        id: 'table',
        name: 'Table',
        iconName: 'desk',
        category: 'neutral',
        gridX: 3,
        gridY: 3,
        width: 2,
        height: 1,
      ),
      // Blended pose left the monitor sitting on the lounge table.
      FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 3.2,
        gridY: 3.1,
        width: 0.35,
        height: 0.8,
      ),
      FurnitureItem(
        id: 'pc',
        name: 'PC Tower',
        iconName: 'pc',
        category: 'airflow',
        gridX: 0.1,
        gridY: 0.1,
        width: 0.45,
        height: 0.5,
      ),
    ];

    final mounted = LayoutOptimizerCommon.mountDeskTopItems(
      furniture,
      gridCols: 8,
      gridRows: 8,
    );
    final desk = mounted.firstWhere((f) => f.id == 'desk');
    final table = mounted.firstWhere((f) => f.id == 'table');
    final monitor = mounted.firstWhere((f) => f.id == 'monitor');
    final pc = mounted.firstWhere((f) => f.id == 'pc');

    expect(SurfaceMounts.hostUnder(monitor, mounted)?.id, desk.id);
    expect(SurfaceMounts.hostUnder(pc, mounted)?.id, desk.id);
    expect(SurfaceMounts.hostUnder(monitor, mounted)?.id, isNot(table.id));
  });

  test('TV and plant mount on lounge table, not the work desk', () {
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
        id: 'table',
        name: 'Table',
        iconName: 'desk',
        category: 'neutral',
        gridX: 4,
        gridY: 4,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'tv',
        name: 'TV',
        iconName: 'tv',
        category: 'lighting',
        gridX: 0,
        gridY: 5,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'plant',
        name: 'Plant',
        iconName: 'plant',
        category: 'neutral',
        gridX: 1,
        gridY: 6,
      ),
      FurnitureItem(
        id: 'monitor',
        name: 'Monitor',
        iconName: 'monitor',
        category: 'ergonomics',
        gridX: 3,
        gridY: 6,
        width: 0.35,
        height: 0.8,
      ),
    ];

    final mounted = LayoutOptimizerCommon.mountDeskTopItems(
      furniture,
      gridCols: 8,
      gridRows: 8,
    );
    final table = mounted.firstWhere((f) => f.id == 'table');
    final desk = mounted.firstWhere((f) => f.id == 'desk');
    final tv = mounted.firstWhere((f) => f.id == 'tv');
    final plant = mounted.firstWhere((f) => f.id == 'plant');
    final monitor = mounted.firstWhere((f) => f.id == 'monitor');

    expect(SurfaceMounts.hostUnder(tv, mounted)?.id, table.id);
    expect(SurfaceMounts.hostUnder(plant, mounted)?.id, table.id);
    expect(SurfaceMounts.hostUnder(monitor, mounted)?.id, desk.id);
    expect(tv.height, lessThanOrEqualTo(0.55));
    expect(tv.width, lessThan(table.width));
  });

  test('sofa+TV+table plan parks table under the TV', () {
    final furniture = <FurnitureItem>[
      FurnitureItem(
        id: 'sofa',
        name: 'Sofa',
        iconName: 'sofa',
        category: 'neutral',
        gridX: 0,
        gridY: 0,
        width: 2,
        height: 1,
      ),
      FurnitureItem(
        id: 'tv',
        name: 'TV',
        iconName: 'tv',
        category: 'lighting',
        gridX: 5,
        gridY: 5,
        width: 2,
        height: 0.45,
      ),
      FurnitureItem(
        id: 'table',
        name: 'Table',
        iconName: 'desk',
        category: 'neutral',
        gridX: 1,
        gridY: 5,
        width: 2,
        height: 1,
      ),
    ];
    final targets = <String, ({double x, double y})>{};
    LayoutOptimizerCommon.planPerimeterStorage(
      furniture: furniture,
      targets: targets,
      gridCols: 8,
      gridRows: 8,
      reasons: <String>[],
    );
    expect(targets.containsKey('table'), isTrue);
    expect(targets.containsKey('tv'), isTrue);
    final tableT = targets['table']!;
    final tvT = targets['tv']!;
    final table = furniture.firstWhere((f) => f.id == 'table');
    final tv = furniture.firstWhere((f) => f.id == 'tv').copyWith(
          gridX: tvT.x,
          gridY: tvT.y,
          height: 0.45,
        );
    final host = table.copyWith(gridX: tableT.x, gridY: tableT.y);
    expect(SurfaceMounts.hostUnder(tv, [host, tv])?.id, 'table');
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
    // Oriented side-wall desk seats the chair on the long inward face.
    final nearX = (chair.x - desk.x).abs() < 2.2;
    final nearY = (chair.y - desk.y).abs() < 2.2;
    expect(nearX || nearY, isTrue);
    expect(
      (chair.x - desk.x).abs() + (chair.y - desk.y).abs(),
      lessThan(4.5),
    );
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

    final desk = result.furniture.firstWhere(
      (f) => SurfaceMounts.isDeskHost(f) && !SurfaceMounts.isTableHost(f),
    );
    for (final item in result.furniture.where(SurfaceMounts.isDeskTopItem)) {
      // Plants prefer a lounge table when present; otherwise desk if they fit.
      if (item.iconName == 'plant') {
        final host = SurfaceMounts.hostUnder(item, result.furniture);
        expect(
          host == null || host.id == desk.id || SurfaceMounts.isTableHost(host),
          isTrue,
          reason: 'plant should be on desk/table or a free floor corner',
        );
        continue;
      }
      expect(
        SurfaceMounts.hostUnder(item, result.furniture)?.id,
        desk.id,
        reason: '${item.id} should sit on the desk after Auto-Rig',
      );
    }
  });
}
