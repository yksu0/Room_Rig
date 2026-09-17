import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_setup.dart';

TrackingSample _t({
  required double x,
  required double z,
  double yaw = 0,
  bool stable = true,
  double confidence = 0.8,
}) {
  return TrackingSample(
    cameraPosition: Vec3(x: x, y: 1.5, z: z),
    cameraEulerDegrees: Vec3(x: 0, y: yaw, z: 0),
    trackingStable: stable,
    confidence: confidence,
  );
}

void main() {
  test('lock stays until stable frames and a real pan', () {
    final setup = ScanSetupController();
    for (int i = 0; i < 12; i++) {
      setup.observe(_t(x: 0, z: 0, yaw: 0));
    }
    expect(setup.phase, ScanSessionPhase.lockTracking);

    for (int i = 0; i < 10; i++) {
      setup.observe(_t(x: 0, z: 0, yaw: i * 6.0));
    }
    expect(setup.phase, ScanSessionPhase.sizeRoom);
  });

  test('unstable frames reset the lock streak', () {
    final setup = ScanSetupController();
    for (int i = 0; i < 8; i++) {
      setup.observe(_t(x: 0, z: 0, yaw: i * 8.0));
    }
    setup.observe(_t(x: 0, z: 0, yaw: 80, stable: false, confidence: 0.1));
    for (int i = 0; i < 4; i++) {
      setup.observe(_t(x: 0, z: 0, yaw: 80));
    }
    expect(setup.phase, ScanSessionPhase.lockTracking);
  });

  test('size walk measures room and recenters origin', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.observe(_t(x: 0.0, z: 0.0));
    setup.observe(_t(x: 2.4, z: 0.1));
    setup.observe(_t(x: 2.4, z: 1.8));
    setup.observe(_t(x: 0.1, z: 1.8));
    for (int i = 0; i < 4; i++) {
      setup.observe(_t(x: 2.4, z: 1.8));
    }

    expect(setup.phase, ScanSessionPhase.capture);
    final dims = setup.measuredDimensions()!;
    expect(dims.lengthMeters, closeTo(2.4 + 1.5, 0.05));
    expect(dims.widthMeters, closeTo(1.8 + 1.5, 0.05));
    expect(setup.origin!.x, closeTo(1.2, 0.05));
    expect(setup.origin!.z, closeTo(0.9, 0.05));

    final layout = setup.buildLayout(roomName: 'Test');
    expect(layout.coverageGrid.cols, greaterThanOrEqualTo(5));
    expect(layout.dimensions.lengthMeters, dims.lengthMeters);
  });

  test('manual size advance works at skip threshold', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.observe(_t(x: 0, z: 0));
    setup.observe(_t(x: 1.2, z: 0));
    setup.observe(_t(x: 1.2, z: 0.2));
    setup.observe(_t(x: 1.3, z: 0.1));
    expect(setup.canAdvanceSize, isTrue);
    setup.advanceFromSize();
    expect(setup.phase, ScanSessionPhase.capture);
  });
}
