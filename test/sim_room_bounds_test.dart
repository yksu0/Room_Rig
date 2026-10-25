import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/sim_room_bounds.dart';
import 'package:room_rig/services/airflow_simulator.dart';

void main() {
  group('SimRoomBounds', () {
    test('fallback is classic 6×8×2.7', () {
      expect(SimRoomBounds.fallback.width, 6);
      expect(SimRoomBounds.fallback.depth, 8);
      expect(SimRoomBounds.fallback.height, 2.7);
      expect(SimRoomBounds.fallback.airflowNx, 18);
      expect(SimRoomBounds.fallback.airflowNz, 24);
    });

    test('airflow build uses non-classic width for field + voxels', () {
      const bounds = SimRoomBounds(width: 10, depth: 8, height: 2.7);
      final furniture = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
      final snap = AirflowSimulator.build(
        furniture: furniture,
        optimized: false,
        bounds: bounds,
        particleCount: 20,
        ambientCount: 10,
      );
      expect(snap.field.roomWidth, 10);
      expect(snap.field.roomDepth, 8);
      expect(snap.field.roomHeight, 2.7);
      expect(snap.field.nx, bounds.airflowNx);
      expect(snap.field.nz, bounds.airflowNz);
      expect(snap.field.nx, 30);
      expect(snap.field.vx.length, snap.field.nx * snap.field.ny * snap.field.nz);
    });
  });
}
