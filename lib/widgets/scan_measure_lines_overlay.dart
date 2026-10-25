import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import '../services/scan_pipeline.dart';
import '../theme/app_theme.dart';

/// Lightweight wireframe hints for measure marks (screen-space placeholders).
class ScanMeasureLinesOverlay extends StatelessWidget {
  final List<Vec3> marks;
  final TrackingSample? tracking;

  const ScanMeasureLinesOverlay({
    super.key,
    required this.marks,
    this.tracking,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _MeasureLinesPainter(
          markCount: marks.length,
          hasHit: tracking?.hasSurfaceHit ?? false,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MeasureLinesPainter extends CustomPainter {
  final int markCount;
  final bool hasHit;

  _MeasureLinesPainter({required this.markCount, required this.hasHit});

  @override
  void paint(Canvas canvas, Size size) {
    if (markCount <= 0) return;
    final paint = Paint()
      ..color = (hasHit ? AppColors.cyan : AppColors.amber).withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width * 0.5;
    final cy = size.height * 0.58;
    final radius = size.shortestSide * 0.12;
    for (var i = 0; i < markCount && i < 8; i++) {
      final t = (i / 8) * 3.1415926535 * 2;
      final dx = cx + radius * (1.2 + (i % 3) * 0.15) * (i.isEven ? 1 : -0.85);
      final dy = cy + radius * 0.35 * (i % 4 - 1.5);
      canvas.drawCircle(Offset(dx + 8 * (t % 1), dy), 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeasureLinesPainter oldDelegate) =>
      oldDelegate.markCount != markCount || oldDelegate.hasHit != hasHit;
}
