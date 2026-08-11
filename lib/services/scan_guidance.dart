import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import 'scan_pipeline.dart';

enum ScanTurnAction {
  turnLeft,
  turnRight,
  walkForward,
  holdStill,
  scanInPlace,
}

enum ScanCoachBannerKind {
  trackingLost,
  motionBlur,
  poorLighting,
  lowTexture,
  holdForFinish,
}

class ScanCoachBanner {
  final ScanCoachBannerKind kind;
  final String title;
  final String detail;
  final IconData icon;
  final Color accent;

  const ScanCoachBanner({
    required this.kind,
    required this.title,
    required this.detail,
    required this.icon,
    required this.accent,
  });
}

class ScanCoverageTarget {
  final int scannedCells;
  final int totalCells;
  final int remainingCells;
  final int startCol;
  final int endColExclusive;
  final int startRow;
  final int endRowExclusive;
  final int sectorCol;
  final int sectorRow;
  final int sectorCols;
  final int sectorRows;
  final String targetLabel;
  final double targetWorldX;
  final double targetWorldZ;

  const ScanCoverageTarget({
    required this.scannedCells,
    required this.totalCells,
    required this.remainingCells,
    required this.startCol,
    required this.endColExclusive,
    required this.startRow,
    required this.endRowExclusive,
    required this.sectorCol,
    required this.sectorRow,
    required this.sectorCols,
    required this.sectorRows,
    required this.targetLabel,
    required this.targetWorldX,
    required this.targetWorldZ,
  });

  bool get isComplete => remainingCells <= 0;
}

class ScanDirectionCue {
  final ScanTurnAction action;
  final String headline;
  final String detail;
  final IconData icon;
  final double relativeBearingDegrees;
  final String targetLabel;

  const ScanDirectionCue({
    required this.action,
    required this.headline,
    required this.detail,
    required this.icon,
    required this.relativeBearingDegrees,
    required this.targetLabel,
  });
}

/// Pure helpers for “where next” + mistake-prevention coach copy.
class ScanGuidance {
  static const double scannedCellThreshold = 0.70;
  static const double forwardBearingDeg = 35;
  static const double inPlaceBearingDeg = 12;

  /// Weakest coverage sector on a floor-plan grid (row 0 = top / +Z start).
  static ScanCoverageTarget? findWeakestSector({
    required CoverageGrid grid,
    required RoomDimensions dimensions,
  }) {
    final total = grid.coverage.length;
    final scanned = grid.coverage.where((v) => v >= scannedCellThreshold).length;
    final remaining = (total - scanned).clamp(0, total);
    final cols = grid.cols;
    final rows = grid.rows;
    if (cols <= 0 || rows <= 0 || total == 0) return null;

    final sectorCols = cols >= 3 ? 3 : cols;
    final sectorRows = rows >= 3 ? 3 : rows;
    final sectorCount = sectorCols * sectorRows;
    final sums = List<double>.filled(sectorCount, 0);
    final counts = List<int>.filled(sectorCount, 0);

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final idx = row * cols + col;
        if (idx >= grid.coverage.length) continue;
        final sx = ((col * sectorCols) / cols).floor().clamp(0, sectorCols - 1);
        final sy = ((row * sectorRows) / rows).floor().clamp(0, sectorRows - 1);
        final sIdx = sy * sectorCols + sx;
        sums[sIdx] += grid.coverage[idx].clamp(0, 1).toDouble();
        counts[sIdx] += 1;
      }
    }

    var bestIdx = 0;
    var bestCoverage = double.infinity;
    for (int i = 0; i < sectorCount; i++) {
      final avg = counts[i] == 0 ? 1.0 : (sums[i] / counts[i]);
      if (avg < bestCoverage) {
        bestCoverage = avg;
        bestIdx = i;
      }
    }

    final sectorCol = bestIdx % sectorCols;
    final sectorRow = bestIdx ~/ sectorCols;
    final startCol = ((sectorCol * cols) / sectorCols).floor().clamp(0, cols - 1);
    final endCol = (((sectorCol + 1) * cols) / sectorCols).ceil().clamp(startCol + 1, cols);
    final startRow = ((sectorRow * rows) / sectorRows).floor().clamp(0, rows - 1);
    final endRow = (((sectorRow + 1) * rows) / sectorRows).ceil().clamp(startRow + 1, rows);

    final midCol = (startCol + endCol) / 2.0;
    final midRow = (startRow + endRow) / 2.0;
    final targetWorldX = (midCol / cols) * dimensions.lengthMeters;
    final targetWorldZ = (midRow / rows) * dimensions.widthMeters;

    return ScanCoverageTarget(
      scannedCells: scanned,
      totalCells: total,
      remainingCells: remaining,
      startCol: startCol,
      endColExclusive: endCol,
      startRow: startRow,
      endRowExclusive: endRow,
      sectorCol: sectorCol,
      sectorRow: sectorRow,
      sectorCols: sectorCols,
      sectorRows: sectorRows,
      targetLabel: sectorLabel(
        row: sectorRow,
        col: sectorCol,
        rows: sectorRows,
        cols: sectorCols,
      ),
      targetWorldX: targetWorldX,
      targetWorldZ: targetWorldZ,
    );
  }

  static String sectorLabel({
    required int row,
    required int col,
    required int rows,
    required int cols,
  }) {
    final vertical = row == 0 ? 'Top' : (row == rows - 1 ? 'Bottom' : 'Middle');
    final horizontal = col == 0 ? 'Left' : (col == cols - 1 ? 'Right' : 'Center');
    if (rows == 1 && cols == 1) return 'Center';
    if (rows == 1) return horizontal;
    if (cols == 1) return vertical;
    return '$vertical-$horizontal';
  }

  /// Bearing of a world target relative to camera yaw (degrees, -180..180).
  /// Yaw uses the same convention as ARCore bridge: atan2(forwardX, forwardZ).
  static double relativeBearingDegrees({
    required double cameraX,
    required double cameraZ,
    required double yawDegrees,
    required double targetX,
    required double targetZ,
  }) {
    final dx = targetX - cameraX;
    final dz = targetZ - cameraZ;
    if (dx.abs() < 1e-4 && dz.abs() < 1e-4) return 0;
    final targetBearing = math.atan2(dx, dz) * 180 / math.pi;
    return normalizeSignedDegrees(targetBearing - yawDegrees);
  }

  static double normalizeSignedDegrees(double degrees) {
    var d = degrees % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  static ScanDirectionCue directionCue({
    required ScanCoverageTarget target,
    required double cameraX,
    required double cameraZ,
    required double yawDegrees,
    required bool coverageReadyForFinish,
  }) {
    if (target.isComplete || coverageReadyForFinish) {
      return ScanDirectionCue(
        action: ScanTurnAction.holdStill,
        headline: 'Hold still',
        detail: 'Coverage is ready — keep the phone steady to lock quality.',
        icon: Icons.front_hand_rounded,
        relativeBearingDegrees: 0,
        targetLabel: target.targetLabel,
      );
    }

    final relative = relativeBearingDegrees(
      cameraX: cameraX,
      cameraZ: cameraZ,
      yawDegrees: yawDegrees,
      targetX: target.targetWorldX,
      targetZ: target.targetWorldZ,
    );
    final absRel = relative.abs();

    if (absRel <= inPlaceBearingDeg) {
      return ScanDirectionCue(
        action: ScanTurnAction.scanInPlace,
        headline: 'Scan here',
        detail: 'You are facing ${target.targetLabel}. Sweep slowly side to side.',
        icon: Icons.center_focus_strong_rounded,
        relativeBearingDegrees: relative,
        targetLabel: target.targetLabel,
      );
    }

    if (absRel <= forwardBearingDeg) {
      return ScanDirectionCue(
        action: ScanTurnAction.walkForward,
        headline: 'Walk forward',
        detail: 'Head toward ${target.targetLabel}, then sweep that area.',
        icon: Icons.arrow_upward_rounded,
        relativeBearingDegrees: relative,
        targetLabel: target.targetLabel,
      );
    }

    if (relative > 0) {
      return ScanDirectionCue(
        action: ScanTurnAction.turnRight,
        headline: 'Turn right',
        detail: 'Rotate toward ${target.targetLabel}, then walk into that zone.',
        icon: Icons.turn_right_rounded,
        relativeBearingDegrees: relative,
        targetLabel: target.targetLabel,
      );
    }

    return ScanDirectionCue(
      action: ScanTurnAction.turnLeft,
      headline: 'Turn left',
      detail: 'Rotate toward ${target.targetLabel}, then walk into that zone.',
      icon: Icons.turn_left_rounded,
      relativeBearingDegrees: relative,
      targetLabel: target.targetLabel,
    );
  }

  /// Highest-priority coach banner, or null when scanning looks healthy.
  static ScanCoachBanner? coachBanner({
    required List<ScanQualityIssue> issues,
    required bool trackingStable,
    required double trackingConfidence,
    required bool coverageReadyForFinish,
    required bool canFinish,
    required int stableQualityFrames,
    required int requiredStableQualityFrames,
  }) {
    final trackingLost = issues.contains(ScanQualityIssue.trackingLost) ||
        !trackingStable ||
        trackingConfidence < 0.35;

    if (trackingLost) {
      return const ScanCoachBanner(
        kind: ScanCoachBannerKind.trackingLost,
        title: 'Tracking lost',
        detail: 'Slow down and point at furniture, corners, or wall edges.',
        icon: Icons.gps_off_rounded,
        accent: Color(0xFFFF3D00),
      );
    }

    if (issues.contains(ScanQualityIssue.motionBlur)) {
      return const ScanCoachBanner(
        kind: ScanCoachBannerKind.motionBlur,
        title: 'Moving too fast',
        detail: 'Reduce walking speed and avoid quick turns.',
        icon: Icons.speed_rounded,
        accent: Color(0xFFFFAB00),
      );
    }

    if (issues.contains(ScanQualityIssue.poorLighting)) {
      return const ScanCoachBanner(
        kind: ScanCoachBannerKind.poorLighting,
        title: 'Too dark',
        detail: 'Face a brighter part of the room or turn on more lights.',
        icon: Icons.wb_sunny_outlined,
        accent: Color(0xFFFFAB00),
      );
    }

    if (issues.contains(ScanQualityIssue.lowTexture)) {
      return const ScanCoachBanner(
        kind: ScanCoachBannerKind.lowTexture,
        title: 'Need more detail',
        detail: 'Include corners, door frames, and objects — not blank walls.',
        icon: Icons.texture_rounded,
        accent: Color(0xFFFFAB00),
      );
    }

    if (coverageReadyForFinish && !canFinish) {
      final left = (requiredStableQualityFrames - stableQualityFrames)
          .clamp(0, requiredStableQualityFrames);
      return ScanCoachBanner(
        kind: ScanCoachBannerKind.holdForFinish,
        title: 'Almost done — hold still',
        detail: left == 0
            ? 'Keep quality stable for a moment, then finish.'
            : 'Hold steady for about $left more good frames.',
        icon: Icons.hourglass_top_rounded,
        accent: const Color(0xFF00E676),
      );
    }

    return null;
  }

  /// Soft 4-corner checklist so edges aren’t skipped when center coverage looks high.
  static List<ScanCornerStatus> cornerChecklist(CoverageGrid grid) {
    final cols = grid.cols;
    final rows = grid.rows;
    if (cols <= 0 || rows <= 0 || grid.coverage.isEmpty) {
      return const [
        ScanCornerStatus(id: 'tl', label: 'TL', done: false),
        ScanCornerStatus(id: 'tr', label: 'TR', done: false),
        ScanCornerStatus(id: 'bl', label: 'BL', done: false),
        ScanCornerStatus(id: 'br', label: 'BR', done: false),
      ];
    }

    final xSplit = (cols / 2).ceil().clamp(1, cols);
    final ySplit = (rows / 2).ceil().clamp(1, rows);

    bool quadrantDone(int c0, int c1, int r0, int r1) {
      var sum = 0.0;
      var n = 0;
      for (int r = r0; r < r1; r++) {
        for (int c = c0; c < c1; c++) {
          final idx = r * cols + c;
          if (idx >= grid.coverage.length) continue;
          sum += grid.coverage[idx].clamp(0.0, 1.0);
          n++;
        }
      }
      if (n == 0) return false;
      return (sum / n) >= 0.55;
    }

    return [
      ScanCornerStatus(
        id: 'tl',
        label: 'TL',
        done: quadrantDone(0, xSplit, 0, ySplit),
      ),
      ScanCornerStatus(
        id: 'tr',
        label: 'TR',
        done: quadrantDone(xSplit, cols, 0, ySplit),
      ),
      ScanCornerStatus(
        id: 'bl',
        label: 'BL',
        done: quadrantDone(0, xSplit, ySplit, rows),
      ),
      ScanCornerStatus(
        id: 'br',
        label: 'BR',
        done: quadrantDone(xSplit, cols, ySplit, rows),
      ),
    ];
  }
}

class ScanCornerStatus {
  final String id;
  final String label;
  final bool done;

  const ScanCornerStatus({
    required this.id,
    required this.label,
    required this.done,
  });
}
