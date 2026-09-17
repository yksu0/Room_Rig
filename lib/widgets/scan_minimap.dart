import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import '../services/scan_guidance.dart';
import '../theme/app_theme.dart';

/// Floor-plan coverage: filled = scanned, outlined = still needed, triangle = you.
class ScanMinimap extends StatelessWidget {
  final CoverageGrid grid;
  final ScanCoverageTarget? target;
  final double cameraX;
  final double cameraZ;
  final double yawDegrees;
  final RoomDimensions dimensions;
  final double coverageRatio;
  final bool compact;

  const ScanMinimap({
    super.key,
    required this.grid,
    required this.dimensions,
    required this.cameraX,
    required this.cameraZ,
    required this.yawDegrees,
    required this.coverageRatio,
    this.target,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final mapSize = compact ? 72.0 : 108.0;
    return Container(
      width: compact ? 88 : 124,
      padding: EdgeInsets.fromLTRB(compact ? 6 : 8, compact ? 6 : 8, compact ? 6 : 8, compact ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: mapSize,
            height: mapSize,
            child: CustomPaint(
              painter: _ScanMinimapPainter(
                grid: grid,
                target: target,
                cameraX: cameraX,
                cameraZ: cameraZ,
                yawDegrees: yawDegrees,
                dimensions: dimensions,
              ),
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            compact ? 'you' : 'you · facing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanMinimapPainter extends CustomPainter {
  final CoverageGrid grid;
  final ScanCoverageTarget? target;
  final double cameraX;
  final double cameraZ;
  final double yawDegrees;
  final RoomDimensions dimensions;

  const _ScanMinimapPainter({
    required this.grid,
    required this.target,
    required this.cameraX,
    required this.cameraZ,
    required this.yawDegrees,
    required this.dimensions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.cols <= 0 || grid.rows <= 0) return;

    final room = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(room, const Radius.circular(8)),
      Paint()..color = const Color(0xFF10141A),
    );

    final cellW = size.width / grid.cols;
    final cellH = size.height / grid.rows;

    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.cols; col++) {
        final idx = row * grid.cols + col;
        if (idx >= grid.coverage.length) continue;
        final v = grid.coverage[idx].clamp(0.0, 1.0);
        final scanned = v >= ScanGuidance.scannedCellThreshold;
        final rect = Rect.fromLTWH(col * cellW + 0.6, row * cellH + 0.6, cellW - 1.2, cellH - 1.2);
        canvas.drawRect(
          rect,
          Paint()
            ..color = scanned
                ? AppColors.cyan.withValues(alpha: 0.55 + v * 0.35)
                : Colors.white.withValues(alpha: 0.06 + v * 0.12),
        );
      }
    }

    final focus = target;
    if (focus != null && !focus.isComplete) {
      final focusRect = Rect.fromLTWH(
        focus.startCol * cellW,
        focus.startRow * cellH,
        (focus.endColExclusive - focus.startCol) * cellW,
        (focus.endRowExclusive - focus.startRow) * cellH,
      );
      canvas.drawRect(
        focusRect.deflate(1),
        Paint()
          ..color = AppColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final len = math.max(0.001, dimensions.lengthMeters);
    final wid = math.max(0.001, dimensions.widthMeters);
    final px = ((cameraX / len).clamp(0.04, 0.96)) * size.width;
    final py = ((cameraZ / wid).clamp(0.04, 0.96)) * size.height;

    // Yaw 0 = facing +Z (toward bottom of this map). +90 = facing +X (right).
    // Draw the tip along that forward vector instead of canvas.rotate + "up".
    final yawRad = yawDegrees * math.pi / 180.0;
    final fx = math.sin(yawRad);
    final fz = math.cos(yawRad);
    final pxp = -fz; // perpendicular
    final pzp = fx;
    const tipLen = 9.0;
    const backLen = 5.0;
    const halfWidth = 5.5;
    final tip = Offset(fx * tipLen, fz * tipLen);
    final back = Offset(-fx * backLen, -fz * backLen);
    final notch = Offset(-fx * 2.0, -fz * 2.0);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + pxp * halfWidth, back.dy + pzp * halfWidth)
      ..lineTo(notch.dx, notch.dy)
      ..lineTo(back.dx - pxp * halfWidth, back.dy - pzp * halfWidth)
      ..close();

    canvas.save();
    canvas.translate(px, py);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScanMinimapPainter old) =>
      old.grid != grid ||
      old.target != target ||
      old.cameraX != cameraX ||
      old.cameraZ != cameraZ ||
      old.yawDegrees != yawDegrees ||
      old.dimensions != dimensions;
}
