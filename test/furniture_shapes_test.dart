import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/widgets/furniture_shapes.dart';

void main() {
  test('chair backrest turns with yaw, not only the facing arrow', () {
    FurnitureBox backrest(double yaw) {
      final parts = FurnitureShapes.boxes(
        kind: FurnitureKind.chair,
        x: 0,
        z: 0,
        width: 1,
        depth: 1,
        color: const Color(0xFFFFFFFF),
        yawDegrees: yaw,
      );
      return parts.reduce((a, b) => a.y1 >= b.y1 ? a : b);
    }

    final facingSouth = backrest(0);
    final facingEast = backrest(90);

    expect(facingSouth.z1 - facingSouth.z0, lessThan(0.35), reason: 'back is a thin slab on Z');
    expect(facingSouth.z0, lessThan(0.35), reason: 'yaw 0 puts the back on the -Z side');
    expect(facingEast.x1 - facingEast.x0, lessThan(0.35), reason: 'after 90° the back is a thin slab on X');
    expect(facingEast.x0, lessThan(0.35), reason: 'yaw 90 puts the back on the -X side');
  });

  test('wall AC is not drawn as a floor mesh', () {
    final ac = FurnitureItem(
      id: 'ac',
      name: 'Wall AC',
      iconName: 'ac',
      category: 'airflow',
      gridX: 0,
      gridY: 0,
    );
    expect(FurnitureShapes.drawsMesh(ac), isFalse);
  });

  test('monitor on a desk is raised to the desk top', () {
    final desk = FurnitureItem(
      id: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'ergonomics',
      gridX: 1,
      gridY: 1,
      width: 2,
      height: 1,
    );
    final monitor = FurnitureItem(
      id: 'monitor',
      name: 'Monitor',
      iconName: 'monitor',
      category: 'lighting',
      gridX: 1.4,
      gridY: 1.2,
      width: 0.6,
      height: 0.2,
    );
    expect(FurnitureShapes.drawsMesh(monitor), isTrue);
    expect(FurnitureShapes.yBaseFor(monitor, [desk, monitor]), FurnitureShapes.deskTopY);
  });

  test('retainV1 drops kitchen, purifier and upgrade leftovers', () {
    final kept = RigCatalog.retainV1([
      FurnitureItem(id: 'chair', name: 'Chair', iconName: 'chair', category: 'ergonomics', gridX: 0, gridY: 0),
      FurnitureItem(id: 'kitchen', name: 'Kitchen Counter', iconName: 'kitchen', category: 'neutral', gridX: 0, gridY: 0),
      FurnitureItem(id: 'upg_purifier', name: 'Smart Air Purifier', iconName: 'purifier', category: 'airflow', gridX: 1, gridY: 1),
      FurnitureItem(id: 'custom_1', name: 'Box', iconName: 'shelf', category: 'neutral', gridX: 2, gridY: 2),
    ]);
    expect(kept.map((f) => f.id), ['chair', 'custom_1']);
  });
}
