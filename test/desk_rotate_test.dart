import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/layout_collision.dart';

void main() {
  test('desk 2x1 rotates to 1x2 in empty room', () {
    final desk = FurnitureItem(
      id: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'ergonomics',
      gridX: 2,
      gridY: 3,
      width: 2,
      height: 1,
    );
    final next = LayoutCollision.rotatedItem(
      id: 'desk',
      deltaDegrees: 90,
      furniture: [desk],
      gridCols: 6,
      gridRows: 8,
    );
    expect(next, isNotNull);
    expect(next!.width, 1);
    expect(next.height, 2);
    expect(next.yawDegrees, 90);
  });

  test('gamingSetup desk rotate against neighbors', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final desk = room.furniture.firstWhere((f) => f.id == 'desk');
    expect(desk.width, 2);
    expect(desk.height, 1);
    final next = LayoutCollision.rotatedItem(
      id: 'desk',
      deltaDegrees: 90,
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    expect(
      next,
      isNotNull,
      reason: 'desk rotate blocked — footprint will not change in UI',
    );
    expect(next!.width, 1);
    expect(next.height, 2);
  });
}
