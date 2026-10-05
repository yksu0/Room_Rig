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
  Vec3? lookAt,
  bool hasFloorHit = false,
}) {
  return TrackingSample(
    cameraPosition: Vec3(x: x, y: 1.5, z: z),
    cameraEulerDegrees: Vec3(x: 0, y: yaw, z: 0),
    trackingStable: stable,
    confidence: confidence,
    lookAtPosition: lookAt,
    hasFloorHit: hasFloorHit,
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
    expect(setup.phase, ScanSessionPhase.markFootprint);
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

  test('three floor marks fit AABB dimensions with pad', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    expect(setup.addMark(const Vec3(x: 0, y: 0, z: 0)), isTrue);
    expect(setup.addMark(const Vec3(x: 2.4, y: 0, z: 0)), isTrue);
    expect(setup.addMark(const Vec3(x: 2.4, y: 0, z: 1.8)), isTrue);
    expect(setup.canAdvanceMark, isTrue);
    expect(setup.markCount, 3);

    final dims = setup.measuredDimensions()!;
    expect(dims.lengthMeters, closeTo(2.4 + 1.5, 0.05));
    expect(dims.widthMeters, closeTo(1.8 + 1.5, 0.05));
    expect(setup.origin!.x, closeTo(1.2, 0.05));
    expect(setup.origin!.z, closeTo(0.9, 0.05));

    setup.advanceFromMark();
    expect(setup.phase, ScanSessionPhase.confirmSize);

    final layout = setup.buildLayout(roomName: 'Test');
    expect(layout.scanSource, 'ar-measure');
    expect(layout.coverageGrid.cols, greaterThanOrEqualTo(5));
  });

  test('four corners and undo mark', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.addMark(const Vec3(x: 0, y: 0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0, z: 2));
    setup.addMark(const Vec3(x: 0, y: 0, z: 2));
    expect(setup.markCount, 4);
    expect(setup.undoMark(), isTrue);
    expect(setup.markCount, 3);
    expect(setup.canAdvanceMark, isTrue);
  });

  test('sparse blocked-corner marks still clamp to min room', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    // Tiny triangle — pad + clamp should hit minRoomMeters.
    setup.addMark(const Vec3(x: 0, y: 0, z: 0));
    setup.addMark(const Vec3(x: 0.2, y: 0, z: 0));
    setup.addMark(const Vec3(x: 0.1, y: 0, z: 0.15));
    final dims = setup.measuredDimensions()!;
    expect(dims.lengthMeters, ScanSetupController.minRoomMeters);
    expect(dims.widthMeters, ScanSetupController.minRoomMeters);
  });

  test('walk estimate fallback then confirm', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.enableWalkEstimate();
    setup.observe(_t(x: 0.0, z: 0.0));
    setup.observe(_t(x: 2.4, z: 0.1));
    setup.observe(_t(x: 2.4, z: 1.8));
    setup.observe(_t(x: 0.1, z: 1.8));
    expect(setup.canAdvanceMark, isTrue);
    setup.advanceFromMark();
    expect(setup.phase, ScanSessionPhase.confirmSize);
    expect(setup.measuredDimensions(), isNotNull);
  });

  test('manual size skips to confirm', () {
    final setup = ScanSetupController();
    setup.setManualDimensions(
      const RoomDimensions(lengthMeters: 4.0, widthMeters: 3.5, heightMeters: 2.7),
    );
    setup.skipToConfirmSize();
    expect(setup.phase, ScanSessionPhase.confirmSize);
    expect(setup.roomSizeSource, 'manual');
    expect(setup.buildLayout(roomName: 'M').scanSource, 'manual');
  });

  test('returnToMarkFootprint clears confirmed override', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.addMark(const Vec3(x: 0, y: 0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0, z: 2));
    setup.advanceFromMark();
    setup.setConfirmedDimensions(
      const RoomDimensions(lengthMeters: 5.0, widthMeters: 4.0, heightMeters: 2.8),
    );
    expect(setup.measuredDimensions()!.lengthMeters, 5.0);
    setup.returnToMarkFootprint();
    expect(setup.phase, ScanSessionPhase.markFootprint);
    expect(setup.measuredDimensions()!.lengthMeters, closeTo(3 + 1.5, 0.05));
  });

  test('max twenty-four marks for odd rooms', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    for (int i = 0; i < 24; i++) {
      expect(setup.addMark(Vec3(x: i * 0.15, y: i.isEven ? 0.0 : 2.6, z: i * 0.05)), isTrue);
    }
    expect(setup.addMark(const Vec3(x: 9, y: 0, z: 9)), isFalse);
    expect(setup.markCount, 24);
  });

  test('floor plus ceiling marks set height from Y span', () {
    final setup = ScanSetupController();
    setup.advanceFromLock();
    setup.addMark(const Vec3(x: 0, y: 0.0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0.0, z: 0));
    setup.addMark(const Vec3(x: 3, y: 0.0, z: 2));
    setup.addMark(const Vec3(x: 0, y: 0.0, z: 2));
    setup.addMark(const Vec3(x: 0, y: 2.7, z: 0));
    setup.addMark(const Vec3(x: 3, y: 2.7, z: 0));
    setup.addMark(const Vec3(x: 3, y: 2.7, z: 2));
    setup.addMark(const Vec3(x: 0, y: 2.7, z: 2));
    expect(setup.markCount, ScanSetupController.recommendedMarks);
    final dims = setup.measuredDimensions()!;
    expect(dims.heightMeters, closeTo(2.7, 0.05));
  });
}
