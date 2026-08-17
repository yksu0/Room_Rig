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

  const ScanMinimap({
    super.key,
    required this.grid,
    required this.dimensions,
    required this.cameraX,
    required this.cameraZ,
    required this.yawDegrees,
    required this.coverageRatio,
    this.target,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 108,
            height: 108,
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
          const SizedBox(height: 6),
          Text(
            '${(coverageRatio * 100).round()}% scanned',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
    final yaw = yawDegrees * math.pi / 180;

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(yaw);
    final path = Path()
      ..moveTo(0, -8)
      ..lineTo(5.5, 7)
      ..lineTo(0, 4)
      ..lineTo(-5.5, 7)
      ..close();
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
      old.yawDegrees != yawDegrees;
}
