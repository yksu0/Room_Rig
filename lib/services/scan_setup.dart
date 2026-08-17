import 'dart:math' as math;

import '../models/scan_layout_model.dart';
import 'scan_guidance.dart';
import 'scan_pipeline.dart';

enum ScanSessionPhase { lockTracking, sizeRoom, capture }

class ScanSetupSnapshot {
  final ScanSessionPhase phase;
  final double progress;
  final bool canAdvance;
  final String headline;
  final String detail;
  final String stepLabel;

  const ScanSetupSnapshot({
    required this.phase,
    required this.progress,
    required this.canAdvance,
    required this.headline,
    required this.detail,
    required this.stepLabel,
  });
}

/// ARCore warmup + one-walk room sizing. No furniture is recorded here.
class ScanSetupController {
  static const int requiredStableFrames = 10;
  static const double requiredYawSpanDegrees = 45;
  static const double requiredExtentMeters = 1.55;
  static const double skipExtentMeters = 1.15;
  static const double wallPadMeters = 0.75;
  static const double minRoomMeters = 2.6;
  static const double maxRoomMeters = 8.5;
  static const double cellMeters = 0.6;

  ScanSessionPhase phase = ScanSessionPhase.lockTracking;

  int _stableStreak = 0;
  double? _yawRef;
  double _yawSpan = 0;

  double? _minX;
  double? _maxX;
  double? _minZ;
  double? _maxZ;
  int _extentSamples = 0;
  int _readyExtentHold = 0;

  Vec3? get origin {
    if (_minX == null || _maxX == null || _minZ == null || _maxZ == null) return null;
    return Vec3(
      x: (_minX! + _maxX!) * 0.5,
      y: 1.5,
      z: (_minZ! + _maxZ!) * 0.5,
    );
  }

  double get extentMeters {
    if (_minX == null || _maxX == null || _minZ == null || _maxZ == null) return 0;
    return math.max(_maxX! - _minX!, _maxZ! - _minZ!);
  }

  void reset() {
    phase = ScanSessionPhase.lockTracking;
    _stableStreak = 0;
    _yawRef = null;
    _yawSpan = 0;
    _minX = null;
    _maxX = null;
    _minZ = null;
    _maxZ = null;
    _extentSamples = 0;
    _readyExtentHold = 0;
  }

  void observe(TrackingSample tracking) {
    if (phase == ScanSessionPhase.capture) return;

    final stable = tracking.trackingStable && tracking.confidence >= 0.4;
    if (!stable) {
      _stableStreak = 0;
      return;
    }
    _stableStreak += 1;

    final yaw = tracking.cameraEulerDegrees.y;
    _yawRef ??= yaw;
    final span = ScanGuidance.normalizeSignedDegrees(yaw - _yawRef!).abs();
    if (span > _yawSpan) _yawSpan = span;

    if (phase == ScanSessionPhase.lockTracking) {
      if (_lockReady) {
        phase = ScanSessionPhase.sizeRoom;
        _stableStreak = 0;
      }
      return;
    }

    _noteExtent(tracking.cameraPosition);
    if (extentMeters >= requiredExtentMeters) {
      _readyExtentHold += 1;
      if (_readyExtentHold >= 4) {
        phase = ScanSessionPhase.capture;
      }
    } else {
      _readyExtentHold = 0;
    }
  }

  bool get _lockReady =>
      _stableStreak >= requiredStableFrames && _yawSpan >= requiredYawSpanDegrees;

  bool get canAdvanceLock => _lockReady || _stableStreak >= requiredStableFrames * 2;

  bool get canAdvanceSize =>
      extentMeters >= skipExtentMeters && _extentSamples >= 4;

  void advanceFromLock() {
    if (phase == ScanSessionPhase.lockTracking) {
      phase = ScanSessionPhase.sizeRoom;
      _stableStreak = 0;
    }
  }

  void advanceFromSize() {
    if (phase == ScanSessionPhase.sizeRoom && (canAdvanceSize || origin != null)) {
      phase = ScanSessionPhase.capture;
    }
  }

  void skipToCapture() {
    phase = ScanSessionPhase.capture;
  }

  RoomDimensions? measuredDimensions() {
    if (_minX == null || _maxX == null || _minZ == null || _maxZ == null) return null;
    final length = ((_maxX! - _minX!) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
    final width = ((_maxZ! - _minZ!) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
    return RoomDimensions(
      lengthMeters: length.toDouble(),
      widthMeters: width.toDouble(),
      heightMeters: 2.7,
    );
  }

  RoomLayoutModel buildLayout({required String roomName, RoomDimensions? fallback}) {
    final dims = measuredDimensions() ??
        fallback ??
        const RoomDimensions(lengthMeters: 4.2, widthMeters: 3.6, heightMeters: 2.7);
    final cols = (dims.lengthMeters / cellMeters).round().clamp(5, 16);
    final rows = (dims.widthMeters / cellMeters).round().clamp(5, 16);
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dims,
      coverageGrid: CoverageGrid.empty(cols: cols, rows: rows),
      objects: const [],
      detections: const [],
      updatedAt: DateTime.now().toUtc(),
      scanSource: 'scan-seed',
    );
  }

  ScanSetupSnapshot snapshot() {
    switch (phase) {
      case ScanSessionPhase.lockTracking:
        final p = ((_stableStreak / requiredStableFrames) * 0.65 +
                (_yawSpan / requiredYawSpanDegrees) * 0.35)
            .clamp(0.0, 1.0);
        return ScanSetupSnapshot(
          phase: phase,
          progress: p,
          canAdvance: canAdvanceLock,
          stepLabel: '1 / 2  LOCK TRACKING',
          headline: _stableStreak == 0 ? 'Find the floor and a corner' : 'Keep panning slowly',
          detail: _stableStreak == 0
              ? 'Stand by the door. Point at the floor, then sweep toward furniture or a corner — not a blank wall.'
              : 'Hold the phone chest-high and turn your body left and right until this fills up.',
        );
      case ScanSessionPhase.sizeRoom:
        final p = (extentMeters / requiredExtentMeters).clamp(0.0, 1.0);
        return ScanSetupSnapshot(
          phase: phase,
          progress: p,
          canAdvance: canAdvanceSize,
          stepLabel: '2 / 2  SIZE THE ROOM',
          headline: p < 0.35 ? 'Walk toward the far wall' : 'A bit farther…',
          detail: p < 1
              ? 'Take a few slow steps across the room. We are measuring size — furniture comes next.'
              : 'Size locked. Capturing starts automatically.',
        );
      case ScanSessionPhase.capture:
        return const ScanSetupSnapshot(
          phase: ScanSessionPhase.capture,
          progress: 1,
          canAdvance: true,
          stepLabel: 'SCAN',
          headline: 'Scan the room',
          detail: 'Follow the map. Cyan is done, amber is next.',
        );
    }
  }

  void _noteExtent(Vec3 pose) {
    _extentSamples += 1;
    _minX = _minX == null ? pose.x : math.min(_minX!, pose.x);
    _maxX = _maxX == null ? pose.x : math.max(_maxX!, pose.x);
    _minZ = _minZ == null ? pose.z : math.min(_minZ!, pose.z);
    _maxZ = _maxZ == null ? pose.z : math.max(_maxZ!, pose.z);
  }
}
