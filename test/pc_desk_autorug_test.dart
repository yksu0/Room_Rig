import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/item_placement_rules.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';

void main() {
  const weights =
      MultiObjectiveWeights(airflow: 0.7, lighting: 0.7, ergonomics: 0.7);

  test('Auto-Rig keeps PC on desk and inside the room', () {
    final room = RoomPresets.getPreset(RoomPreset.homeOffice);
    final furniture = List<FurnitureItem>.from(room.furniture);
    if (!furniture.any((f) => f.iconName == 'pc')) {
      furniture.add(
        RigCatalog.items
            .firstWhere((e) => e.baseId == 'pc')
            .toFurniture(id: 'pc', gridX: 2, gridY: 2),
      );
    }
    if (!furniture.any((f) => f.iconName == 'monitor')) {
      furniture.add(
        RigCatalog.items
            .firstWhere((e) => e.baseId == 'monitor')
            .toFurniture(id: 'monitor', gridX: 2, gridY: 2),
      );
    }

    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final desk = result.furniture.firstWhere(
      (f) => f.iconName == 'desk' || f.id.contains('desk'),
    );
    final pc = result.furniture.firstWhere((f) => f.iconName == 'pc');
    final host = SurfaceMounts.hostUnder(pc, result.furniture);

    expect(pc.gridX, greaterThanOrEqualTo(-0.01));
    expect(pc.gridY, greaterThanOrEqualTo(-0.01));
    expect(pc.gridX + pc.width, lessThanOrEqualTo(room.gridCols + 0.01));
    expect(pc.gridY + pc.height, lessThanOrEqualTo(room.gridRows + 0.01));
    expect(host?.id, desk.id, reason: 'PC must sit on the desk host');
    expect(
      ItemPlacementRules.deskWorkFace(desk, room.gridCols, room.gridRows),
      anyOf('east', 'west'),
    );
  });

  test('Auto-Rig keeps oversized legacy PC inside room on desk wall', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final result = MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    );
    final desk = result.furniture.firstWhere(
      (f) => f.iconName == 'desk' || f.id.contains('desk'),
    );
    final pc = result.furniture.firstWhere((f) => f.iconName == 'pc');
    expect(pc.gridX, greaterThanOrEqualTo(-0.01));
    expect(pc.gridY, greaterThanOrEqualTo(-0.01));
    expect(pc.gridX + pc.width, lessThanOrEqualTo(room.gridCols + 0.01));
    expect(pc.gridY + pc.height, lessThanOrEqualTo(room.gridRows + 0.01));
    // Prefer on-desk; if footprint is too large, at least stay flush inside.
    final host = SurfaceMounts.hostUnder(pc, result.furniture);
    if (pc.width <= desk.width + 0.05 && pc.height <= desk.height + 0.05) {
      expect(host?.id, desk.id);
    } else {
      expect(pc.gridX, lessThan(1.0), reason: 'oversized PC stays near side wall');
    }
  });
}
