import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';

void main() {
  test('coverage marks the floor hit, not a wide blob under the camera', () {
    final engine = GridCoverageFusionEngine();
    engine.useWorldOrigin(const Vec3(x: 3, y: 1.5, z: 3));
    final seed = RoomLayoutModel(
      roomName: 'Look',
      dimensions: const RoomDimensions(lengthMeters: 6, widthMeters: 6, heightMeters: 2.7),
      coverageGrid: CoverageGrid.empty(cols: 10, rows: 10),
      objects: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final state = engine.initialize(seed);
    final next = engine.fuseFrame(
      current: state,
      frame: const ScanFrameResult(
        tracking: TrackingSample(
          cameraPosition: Vec3(x: 0.4, y: 1.5, z: 0.4),
          cameraEulerDegrees: Vec3(x: -20, y: 0, z: 0),
          trackingStable: true,
          lookAtPosition: Vec3(x: 4.5, y: 0, z: 4.5),
          hasFloorHit: true,
          depthHintMeters: 3.2,
        ),
        quality: ScanQualityReport(acceptable: true, issues: []),
        detections: [],
      ),
    );

    final grid = next.layout.coverageGrid;
    // Camera sits near cell 0,0. Look-at is near cell 7,7.
    expect(grid.coverage[0], lessThan(0.2));
    expect(grid.coverage[7 * 10 + 7], greaterThan(0.9));
  });
}
