import 'dart:math' as math;

import '../models/scan_layout_model.dart';
import 'scan_guidance.dart';
import 'scan_pipeline.dart';

/// Staged Scan: lock tracking → mark footprint → confirm size → Rig.
/// [capture] is retained for optional future furniture pass; default path never enters it.
enum ScanSessionPhase { lockTracking, markFootprint, confirmSize, capture }

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

/// ARCore warmup + floor-mark room sizing. No furniture is recorded here.
class ScanSetupController {
  static const int requiredStableFrames = 10;
  static const double requiredYawSpanDegrees = 45;
  static const double requiredExtentMeters = 1.55;
  static const double skipExtentMeters = 1.15;
  static const double wallPadMeters = 0.75;
  static const double minRoomMeters = 2.6;
  static const double maxRoomMeters = 8.5;
  static const double cellMeters = 0.6;
  static const int minMarks = 3;
  static const int maxMarks = 8;

  ScanSessionPhase phase = ScanSessionPhase.lockTracking;

  int _stableStreak = 0;
  double? _yawRef;
  double _yawSpan = 0;

  double? _minX;
  double? _maxX;
  double? _minZ;
  double? _maxZ;
  int _extentSamples = 0;

  final List<Vec3> _marks = [];
  bool walkEstimateEnabled = false;

  RoomDimensions? _manualDimensions;
  RoomDimensions? _confirmedOverride;

  /// `preset` | `measured` | `manual`
  String roomSizeSource = 'preset';

  List<Vec3> get marks => List.unmodifiable(_marks);

  int get markCount => _marks.length;

  Vec3? get origin {
    final dims = measuredDimensions();
    if (dims == null) return null;
    if (_marks.length >= minMarks) {
      double minX = _marks.first.x, maxX = _marks.first.x;
      double minZ = _marks.first.z, maxZ = _marks.first.z;
      for (final m in _marks) {
        minX = math.min(minX, m.x);
        maxX = math.max(maxX, m.x);
        minZ = math.min(minZ, m.z);
        maxZ = math.max(maxZ, m.z);
      }
      return Vec3(x: (minX + maxX) * 0.5, y: 1.5, z: (minZ + maxZ) * 0.5);
    }
    if (_minX == null || _maxX == null || _minZ == null || _maxZ == null) {
      return Vec3(x: dims.lengthMeters * 0.5, y: 1.5, z: dims.widthMeters * 0.5);
    }
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

  bool get isSizingPhase =>
      phase == ScanSessionPhase.lockTracking ||
      phase == ScanSessionPhase.markFootprint ||
      phase == ScanSessionPhase.confirmSize;

  bool get needsArCoreSession =>
      phase == ScanSessionPhase.lockTracking ||
      phase == ScanSessionPhase.markFootprint;

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
    _marks.clear();
    walkEstimateEnabled = false;
    _manualDimensions = null;
    _confirmedOverride = null;
    roomSizeSource = 'preset';
  }

  void setManualDimensions(RoomDimensions dims) {
    _manualDimensions = RoomDimensions(
      lengthMeters: dims.lengthMeters.clamp(minRoomMeters, maxRoomMeters),
      widthMeters: dims.widthMeters.clamp(minRoomMeters, maxRoomMeters),
      heightMeters: dims.heightMeters.clamp(2.2, 3.5),
    );
    roomSizeSource = 'manual';
  }

  void setConfirmedDimensions(RoomDimensions dims) {
    _confirmedOverride = RoomDimensions(
      lengthMeters: dims.lengthMeters.clamp(minRoomMeters, maxRoomMeters),
      widthMeters: dims.widthMeters.clamp(minRoomMeters, maxRoomMeters),
      heightMeters: dims.heightMeters.clamp(2.2, 3.5),
    );
    if (roomSizeSource == 'preset' && _manualDimensions == null && _marks.isEmpty) {
      roomSizeSource = 'manual';
    }
  }

  /// Drop a floor mark (world XZ). Returns false if not accepting marks.
  bool addMark(Vec3 point) {
    if (phase != ScanSessionPhase.markFootprint) return false;
    if (_marks.length >= maxMarks) return false;
    _marks.add(point);
    if (_marks.length >= minMarks) {
      roomSizeSource = 'measured';
    }
    return true;
  }

  bool undoMark() {
    if (_marks.isEmpty) return false;
    _marks.removeLast();
    if (_marks.length < minMarks &&
        _manualDimensions == null &&
        !walkEstimateEnabled) {
      roomSizeSource = 'preset';
    }
    return true;
  }

  void clearMarks() {
    _marks.clear();
  }

  void enableWalkEstimate() {
    walkEstimateEnabled = true;
  }

  void observe(TrackingSample tracking) {
    if (phase == ScanSessionPhase.confirmSize ||
        phase == ScanSessionPhase.capture) {
      return;
    }

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
        phase = ScanSessionPhase.markFootprint;
        _stableStreak = 0;
      }
      return;
    }

    // markFootprint: optional walk-extent samples (user must still review).
    if (walkEstimateEnabled || _marks.isEmpty) {
      _noteExtent(tracking.cameraPosition);
    }
  }

  bool get _lockReady =>
      _stableStreak >= requiredStableFrames && _yawSpan >= requiredYawSpanDegrees;

  bool get canAdvanceLock => _lockReady || _stableStreak >= requiredStableFrames * 2;

  bool get canAdvanceMark =>
      _manualDimensions != null ||
      _marks.length >= minMarks ||
      (walkEstimateEnabled &&
          extentMeters >= skipExtentMeters &&
          _extentSamples >= 4);

  void advanceFromLock() {
    if (phase == ScanSessionPhase.lockTracking) {
      phase = ScanSessionPhase.markFootprint;
      _stableStreak = 0;
    }
  }

  /// Move from mark footprint → confirm size (does not start YOLO capture).
  void advanceFromMark() {
    if (phase != ScanSessionPhase.markFootprint) return;
    if (!canAdvanceMark && origin == null && _manualDimensions == null) return;
    if (_manualDimensions == null && measuredDimensions() != null) {
      if (_marks.length >= minMarks || walkEstimateEnabled) {
        roomSizeSource = 'measured';
      }
    }
    phase = ScanSessionPhase.confirmSize;
  }

  /// @deprecated Use [advanceFromMark]; kept for call-site compatibility.
  void advanceFromSize() => advanceFromMark();

  void skipToConfirmSize({bool asPreset = false}) {
    phase = ScanSessionPhase.confirmSize;
    if (asPreset && _manualDimensions == null && measuredDimensions() == null) {
      roomSizeSource = 'preset';
    } else if (_manualDimensions == null && measuredDimensions() == null) {
      roomSizeSource = 'preset';
    }
  }

  void returnToMarkFootprint() {
    if (phase == ScanSessionPhase.confirmSize) {
      phase = ScanSessionPhase.markFootprint;
      _confirmedOverride = null;
    }
  }

  /// @deprecated Prefer [skipToConfirmSize] — capture is no longer the default end.
  void skipToCapture() => skipToConfirmSize(asPreset: true);

  RoomDimensions? measuredDimensions() {
    if (_confirmedOverride != null) return _confirmedOverride;
    if (_manualDimensions != null) return _manualDimensions;

    if (_marks.length >= minMarks) {
      double minX = _marks.first.x, maxX = _marks.first.x;
      double minZ = _marks.first.z, maxZ = _marks.first.z;
      for (final m in _marks) {
        minX = math.min(minX, m.x);
        maxX = math.max(maxX, m.x);
        minZ = math.min(minZ, m.z);
        maxZ = math.max(maxZ, m.z);
      }
      final length =
          ((maxX - minX) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
      final width =
          ((maxZ - minZ) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
      return RoomDimensions(
        lengthMeters: length.toDouble(),
        widthMeters: width.toDouble(),
        heightMeters: 2.7,
      );
    }

    if (_minX == null || _maxX == null || _minZ == null || _maxZ == null) {
      return null;
    }
    final length =
        ((_maxX! - _minX!) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
    final width =
        ((_maxZ! - _minZ!) + wallPadMeters * 2).clamp(minRoomMeters, maxRoomMeters);
    return RoomDimensions(
      lengthMeters: length.toDouble(),
      widthMeters: width.toDouble(),
      heightMeters: 2.7,
    );
  }

  RoomLayoutModel buildLayout({required String roomName, RoomDimensions? fallback}) {
    final measured = measuredDimensions();
    final dims = measured ??
        fallback ??
        const RoomDimensions(lengthMeters: 4.2, widthMeters: 3.6, heightMeters: 2.7);
    if (_manualDimensions == null &&
        _confirmedOverride == null &&
        measured == null) {
      roomSizeSource = 'preset';
    }
    final cols = (dims.lengthMeters / cellMeters).round().clamp(5, 16);
    final rows = (dims.widthMeters / cellMeters).round().clamp(5, 16);
    final source = switch (roomSizeSource) {
      'manual' => 'manual',
      'measured' => 'ar-measure',
      _ => 'scan-seed',
    };
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dims,
      coverageGrid: CoverageGrid.empty(cols: cols, rows: rows),
      objects: const [],
      detections: const [],
      updatedAt: DateTime.now().toUtc(),
      scanSource: source,
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
          stepLabel: '1 / 3  LOCK TRACKING',
          headline: _stableStreak == 0 ? 'Find the floor and a corner' : 'Keep panning slowly',
          detail: _stableStreak == 0
              ? 'Stand by the door. Point at the floor, then sweep toward a wall or corner.'
              : 'Hold the phone chest-high and turn slowly until this fills up.',
        );
      case ScanSessionPhase.markFootprint:
        final p = (_marks.length / minMarks).clamp(0.0, 1.0);
        return ScanSetupSnapshot(
          phase: phase,
          progress: walkEstimateEnabled
              ? (extentMeters / requiredExtentMeters).clamp(0.0, 1.0)
              : p,
          canAdvance: canAdvanceMark,
          stepLabel: '2 / 3  MARK CORNERS',
          headline: _marks.isEmpty
              ? 'Aim at a corner or wall base — Drop mark'
              : 'Marks ${_marks.length} / $maxMarks'
                  '${_marks.length >= minMarks ? ' — ready to review' : ''}',
          detail: _marks.length < minMarks
              ? 'Tap Drop mark on visible corners. If a corner is blocked, mark the nearest wall point instead (need $minMarks+).'
              : 'Add more corners if you can, or Review size. Blocked corners: edit L×W on the next screen.',
        );
      case ScanSessionPhase.confirmSize:
        final d = measuredDimensions();
        return ScanSetupSnapshot(
          phase: phase,
          progress: 1,
          canAdvance: true,
          stepLabel: '3 / 3  CONFIRM SIZE',
          headline: 'Confirm room size',
          detail: d == null
              ? 'Enter length × width, then continue to Rig.'
              : 'Approx ${d.lengthMeters.toStringAsFixed(1)} × ${d.widthMeters.toStringAsFixed(1)} m — edit if a corner was blocked, then open Rig.',
        );
      case ScanSessionPhase.capture:
        return const ScanSetupSnapshot(
          phase: ScanSessionPhase.capture,
          progress: 1,
          canAdvance: true,
          stepLabel: 'SCAN',
          headline: 'Optional capture',
          detail: 'Furniture capture is optional — default path goes to Rig after size.',
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
