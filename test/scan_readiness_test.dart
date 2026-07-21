import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_readiness.dart';

void main() {
  group('ScanFinishReadinessController', () {
    test('requires stable quality window before canFinish flips true', () {
      final controller = ScanFinishReadinessController(
        requiredCoverage: 0.90,
        requiredStableQualityFrames: 3,
        qualitySmoothingAlpha: 1.0,
      );

      final good = const ScanQualityReport(acceptable: true, issues: []);

      final s1 = controller.update(coverageRatio: 0.92, quality: good);
      final s2 = controller.update(coverageRatio: 0.92, quality: good);
      final s3 = controller.update(coverageRatio: 0.92, quality: good);

      expect(s1.canFinish, isFalse);
      expect(s2.canFinish, isFalse);
      expect(s3.canFinish, isTrue);
    });

    test('hysteresis keeps canFinish true on small temporary dips', () {
      final controller = ScanFinishReadinessController(
        requiredCoverage: 0.90,
        requiredStableQualityFrames: 2,
        qualitySmoothingAlpha: 1.0,
      );

      final good = const ScanQualityReport(acceptable: true, issues: []);
      controller.update(coverageRatio: 0.95, quality: good);
      final ready = controller.update(coverageRatio: 0.95, quality: good);

      final stillReady = controller.update(coverageRatio: 0.88, quality: good);
      final dropped = controller.update(
        coverageRatio: 0.84,
        quality: const ScanQualityReport(
          acceptable: false,
          issues: [ScanQualityIssue.trackingLost],
        ),
      );

      expect(ready.canFinish, isTrue);
      expect(stillReady.canFinish, isTrue);
      expect(dropped.canFinish, isFalse);
    });

    test('quality penalties reduce score and decay stable frame counter', () {
      final controller = ScanFinishReadinessController(
        requiredCoverage: 0.90,
        requiredStableQualityFrames: 3,
        qualitySmoothingAlpha: 1.0,
      );

      final good = const ScanQualityReport(acceptable: true, issues: []);
      controller.update(coverageRatio: 0.92, quality: good);
      controller.update(coverageRatio: 0.92, quality: good);
      controller.update(coverageRatio: 0.92, quality: good);
      expect(controller.canFinish, isTrue);

      controller.update(
        coverageRatio: 0.92,
        quality: const ScanQualityReport(
          acceptable: false,
          issues: [ScanQualityIssue.motionBlur, ScanQualityIssue.poorLighting],
        ),
      );

      expect(controller.smoothedQuality, lessThan(0.70));
      expect(controller.stableQualityFrames, lessThan(3));
    });
  });
}
