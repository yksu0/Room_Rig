import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/item_detection.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/services/scan_pipeline.dart';

void main() {
  group('ItemDetection', () {
    test('round-trips through JSON', () {
      const det = ItemDetection(
        id: 'det_1_0',
        label: 'Chair',
        category: 'ergonomics',
        bbox: BBox2D(left: 0.1, top: 0.2, width: 0.3, height: 0.4),
        confidence: 0.82,
        sourceFrame: 12,
      );
      final decoded = ItemDetection.fromJson(det.toJson());
      expect(decoded.id, 'det_1_0');
      expect(decoded.label, 'Chair');
      expect(decoded.bbox.width, 0.3);
      expect(decoded.sourceFrame, 12);
      expect(decoded.confidence, closeTo(0.82, 1e-9));
    });

    test('Detection2D maps into ItemDetection', () {
      const d = Detection2D(
        label: 'Desk',
        category: 'ergonomics',
        confidence: 0.9,
        left: 0.2,
        top: 0.3,
        width: 0.25,
        height: 0.2,
      );
      final item = d.toItemDetection(id: 'det_3_1', sourceFrame: 3);
      expect(item.id, 'det_3_1');
      expect(item.sourceFrame, 3);
      expect(item.bbox.left, 0.2);
      expect(item.label, 'Desk');
    });
  });

  group('LayoutCollision', () {
    test('resolveMove blocks overlapping placements', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final furniture = room.furniture.map((f) => f.copyWith()).toList();
      final desk = furniture.firstWhere((f) => f.id == 'desk');

      // Force a deep overlap with no free axis slide (park chair centered on desk).
      final blocked = LayoutCollision.resolveMove(
        id: 'chair',
        proposedX: desk.gridX + 0.5,
        proposedY: desk.gridY,
        furniture: furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      final chair = furniture.firstWhere((f) => f.id == 'chair');
      final landed = chair.copyWith(gridX: blocked.gridX, gridY: blocked.gridY);
      expect(LayoutCollision.overlaps(landed, desk), isFalse);
      expect(blocked.gridX == desk.gridX + 0.5 && blocked.gridY == desk.gridY, isFalse);
    });

    test('resolveMove allows free space with snap', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final furniture = room.furniture.map((f) => f.copyWith()).toList();
      final lampMove = LayoutCollision.resolveMove(
        id: 'lamp',
        proposedX: 0.12,
        proposedY: 6.88,
        furniture: furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      expect(lampMove.blocked, isFalse);
      expect(lampMove.gridX, 0.0);
      expect(lampMove.gridY, 7.0);
    });

    test('findConflicts reports overlaps', () {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final furniture = room.furniture.map((f) {
        if (f.id == 'chair') return f.copyWith(gridX: 1, gridY: 1);
        return f.copyWith();
      }).toList();
      final conflicts = LayoutCollision.findConflicts(
        furniture: furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      expect(conflicts.any((c) => c.kind == LayoutConflictKind.overlap), isTrue);
    });
  });
}
