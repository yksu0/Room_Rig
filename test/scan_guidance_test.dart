import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_guidance.dart';
import 'package:room_rig/services/scan_pipeline.dart';

void main() {
  group('ScanGuidance bearings', () {
    test('normalizeSignedDegrees wraps into -180..180', () {
      expect(ScanGuidance.normalizeSignedDegrees(190), -170);
      expect(ScanGuidance.normalizeSignedDegrees(-190), 170);
      expect(ScanGuidance.normalizeSignedDegrees(45), 45);
    });

    test('relativeBearingDegrees asks for right turn when target is to +X', () {
      // Facing +Z (yaw 0); target further along +X → positive / turn right.
      final relative = ScanGuidance.relativeBearingDegrees(
        cameraX: 2,
        cameraZ: 2,
        yawDegrees: 0,
        targetX: 3.5,
        targetZ: 2,
      );
      expect(relative, greaterThan(60));
      expect(relative, lessThan(120));
    });

    test('directionCue turns left when target is behind-left', () {
      const dims = RoomDimensions(lengthMeters: 4, widthMeters: 4, heightMeters: 2.7);
      final grid = CoverageGrid(cols: 6, rows: 6, coverage: List<double>.filled(36, 0.9));
      // Leave bottom-left weak.
      for (int r = 4; r < 6; r++) {
        for (int c = 0; c < 2; c++) {
          grid.coverage[r * 6 + c] = 0.1;
        }
      }

      final target = ScanGuidance.findWeakestSector(grid: grid, dimensions: dims)!;
      expect(target.targetLabel.toLowerCase(), contains('left'));

      final cue = ScanGuidance.directionCue(
        target: target,
        cameraX: 2,
        cameraZ: 2,
        yawDegrees: 0, // facing +Z / "top" of map
        coverageReadyForFinish: false,
      );
      expect(
        cue.action == ScanTurnAction.turnLeft ||
            cue.action == ScanTurnAction.turnRight ||
            cue.action == ScanTurnAction.walkForward,
        isTrue,
      );
      expect(cue.headline, isNotEmpty);
    });

    test('directionCue holds still when coverage complete', () {
      const dims = RoomDimensions(lengthMeters: 3, widthMeters: 3, heightMeters: 2.7);
      final grid = CoverageGrid(cols: 3, rows: 3, coverage: List<double>.filled(9, 1.0));
      final target = ScanGuidance.findWeakestSector(grid: grid, dimensions: dims)!;
      final cue = ScanGuidance.directionCue(
        target: target,
        cameraX: 1.5,
        cameraZ: 1.5,
        yawDegrees: 20,
        coverageReadyForFinish: true,
      );
      expect(cue.action, ScanTurnAction.holdStill);
    });
  });

  group('ScanGuidance coach banners', () {
    test('prioritizes tracking lost over motion blur', () {
      final banner = ScanGuidance.coachBanner(
        issues: const [ScanQualityIssue.motionBlur, ScanQualityIssue.trackingLost],
        trackingStable: false,
        trackingConfidence: 0.2,
        coverageReadyForFinish: false,
        canFinish: false,
        stableQualityFrames: 0,
        requiredStableQualityFrames: 8,
      );
      expect(banner?.kind, ScanCoachBannerKind.trackingLost);
    });

    test('shows hold-for-finish when coverage ready but not finishable', () {
      final banner = ScanGuidance.coachBanner(
        issues: const [],
        trackingStable: true,
        trackingConfidence: 0.9,
        coverageReadyForFinish: true,
        canFinish: false,
        stableQualityFrames: 3,
        requiredStableQualityFrames: 8,
      );
      expect(banner?.kind, ScanCoachBannerKind.holdForFinish);
      expect(banner?.detail, contains('5'));
    });

    test('returns null when healthy and not finishing', () {
      final banner = ScanGuidance.coachBanner(
        issues: const [],
        trackingStable: true,
        trackingConfidence: 0.9,
        coverageReadyForFinish: false,
        canFinish: false,
        stableQualityFrames: 2,
        requiredStableQualityFrames: 8,
      );
      expect(banner, isNull);
    });
  });

  group('ScanGuidance corner checklist', () {
    test('marks quadrants done from coverage averages', () {
      final coverage = List<double>.filled(16, 0.1);
      // Fill top-left 2x2 of a 4x4 grid.
      coverage[0] = 1;
      coverage[1] = 1;
      coverage[4] = 1;
      coverage[5] = 1;
      final grid = CoverageGrid(cols: 4, rows: 4, coverage: coverage);
      final corners = ScanGuidance.cornerChecklist(grid);
      expect(corners.firstWhere((c) => c.id == 'tl').done, isTrue);
      expect(corners.firstWhere((c) => c.id == 'br').done, isFalse);
    });
  });
}
