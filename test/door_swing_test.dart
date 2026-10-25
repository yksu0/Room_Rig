import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/door_swing.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/layout_collision.dart';

void main() {
  test('door swing solid arc is a quarter-circle; dashed half completes semicircle', () {
    const span = WallSpan(
      wall: RoomWall.north,
      x0: 2,
      z0: 0,
      x1: 4,
      z1: 0,
      inwardX: 0,
      inwardZ: 1,
    );
    final swing = DoorSwingGeometry.fromSpan(span);
    expect(swing.radius, 2);
    expect(swing.hingeX, 2);
    expect(swing.hingeZ, 0);

    final closed = swing.pointAt(0);
    expect(closed.$1, closeTo(4, 1e-9));
    expect(closed.$2, closeTo(0, 1e-9));

    final open = swing.pointAt(1);
    expect(open.$1, closeTo(2, 1e-9));
    expect(open.$2, closeTo(2, 1e-9));

    final mid = swing.pointAt(0.5);
    final dx = mid.$1 - swing.hingeX;
    final dz = mid.$2 - swing.hingeZ;
    expect(dx * dx + dz * dz, closeTo(swing.radius * swing.radius, 1e-6));

    final opposite = swing.pointAtRadians(math.pi);
    expect(opposite.$1, closeTo(0, 1e-9));
    expect(opposite.$2, closeTo(0, 1e-9));
    final dashed = swing.dashedArcPoints(steps: 8);
    expect(dashed.first.$1, closeTo(open.$1, 1e-9));
    expect(dashed.first.$2, closeTo(open.$2, 1e-9));
    expect(dashed.last.$1, closeTo(opposite.$1, 1e-9));
    expect(dashed.last.$2, closeTo(opposite.$2, 1e-9));
  });

  test('furniture in door swing is blocked by collision', () {
    final door = FurnitureItem(
      id: 'door',
      name: 'Entry Door',
      iconName: 'door',
      category: 'neutral',
      gridX: 0,
      gridY: 3,
      width: 0.25,
      height: 1.5,
    );
    final cols = 6;
    final rows = 8;
    final seated = SurfaceMounts.snapToWall(door, gridCols: cols, gridRows: rows);
    final furniture = [seated];

    final blocker = FurnitureItem(
      id: 'table',
      name: 'Table',
      iconName: 'table',
      category: 'neutral',
      gridX: seated.gridX + 0.3,
      gridY: seated.gridY,
      width: 1.2,
      height: 0.6,
    );

    final swing = DoorSwingGeometry.of(seated, gridCols: cols, gridRows: rows);
    expect(swing, isNotNull);
    expect(swing!.overlapsItem(blocker), isTrue);
    expect(
      LayoutCollision.itemCollides(
        blocker,
        furniture,
        gridCols: cols,
        gridRows: rows,
      ),
      isTrue,
    );

    final clear = blocker.copyWith(gridX: 3, gridY: 3);
    expect(swing.overlapsItem(clear), isFalse);
    expect(
      LayoutCollision.itemCollides(
        clear,
        furniture,
        gridCols: cols,
        gridRows: rows,
      ),
      isFalse,
    );
  });
}
