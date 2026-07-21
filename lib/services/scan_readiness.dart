import 'dart:math' as math;

import 'scan_pipeline.dart';

class ScanReadinessSnapshot {
  final double smoothedQuality;
  final int stableQualityFrames;
  final bool canFinish;
  final bool qualityAcceptableInstant;

  const ScanReadinessSnapshot({
    required this.smoothedQuality,
    required this.stableQualityFrames,
    required this.canFinish,
    required this.qualityAcceptableInstant,
  });
}

class ScanFinishReadinessController {
  final double requiredCoverage;
  final int requiredStableQualityFrames;
  final double qualitySmoothingAlpha;
  final double qualityEnterThreshold;
  final double qualityExitThreshold;
  final double coverageExitSlack;

  double _smoothedQuality = 0;
  int _stableQualityFrames = 0;
  bool _canFinish = false;

  ScanFinishReadinessController({
    required this.requiredCoverage,
    required this.requiredStableQualityFrames,
    this.qualitySmoothingAlpha = 0.25,
    this.qualityEnterThreshold = 0.70,
    this.qualityExitThreshold = 0.58,
    this.coverageExitSlack = 0.03,
  });

  double get smoothedQuality => _smoothedQuality;
  int get stableQualityFrames => _stableQualityFrames;
  bool get canFinish => _canFinish;

  void reset() {
    _smoothedQuality = 0;
    _stableQualityFrames = 0;
    _canFinish = false;
  }

  ScanReadinessSnapshot update({
    required double coverageRatio,
    required ScanQualityReport quality,
  }) {
    final instantQuality = _instantQualityScore(quality);
    if (_smoothedQuality == 0) {
      _smoothedQuality = instantQuality;
    } else {
      _smoothedQuality =
          (qualitySmoothingAlpha * instantQuality) + ((1 - qualitySmoothingAlpha) * _smoothedQuality);
    }

    if (_smoothedQuality >= qualityEnterThreshold) {
      _stableQualityFrames++;
    } else if (_stableQualityFrames > 0) {
      // Decay one step at a time to avoid hard resets from single noisy frames.
      _stableQualityFrames--;
    }

    final meetsEntry = coverageRatio >= requiredCoverage &&
        _stableQualityFrames >= requiredStableQualityFrames &&
        _smoothedQuality >= qualityEnterThreshold;

    final shouldExit = coverageRatio < (requiredCoverage - coverageExitSlack) ||
        _smoothedQuality < qualityExitThreshold;

    if (!_canFinish && meetsEntry) {
      _canFinish = true;
    } else if (_canFinish && shouldExit) {
      _canFinish = false;
    }

    return ScanReadinessSnapshot(
      smoothedQuality: _smoothedQuality,
      stableQualityFrames: _stableQualityFrames,
      canFinish: _canFinish,
      qualityAcceptableInstant: quality.acceptable,
    );
  }

  double _instantQualityScore(ScanQualityReport quality) {
    if (quality.acceptable) {
      return 1.0;
    }

    if (quality.issues.isEmpty) {
      return 0.55;
    }

    final penalties = quality.issues.map(_issuePenalty).fold<double>(0, (a, b) => a + b);
    return math.max(0.0, 1.0 - penalties);
  }

  double _issuePenalty(ScanQualityIssue issue) {
    switch (issue) {
      case ScanQualityIssue.trackingLost:
        return 0.70;
      case ScanQualityIssue.motionBlur:
        return 0.38;
      case ScanQualityIssue.poorLighting:
        return 0.30;
      case ScanQualityIssue.lowTexture:
        return 0.24;
    }
  }
}
