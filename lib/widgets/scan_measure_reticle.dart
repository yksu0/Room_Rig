import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Measure-app style center reticle for AR corner marking.
class ScanMeasureReticle extends StatelessWidget {
  final bool lockedOnSurface;
  final String? surfaceKind;
  final int markCount;
  final int recommendedMarks;

  const ScanMeasureReticle({
    super.key,
    required this.lockedOnSurface,
    this.surfaceKind,
    this.markCount = 0,
    this.recommendedMarks = 8,
  });

  @override
  Widget build(BuildContext context) {
    final accent = lockedOnSurface ? AppColors.cyan : AppColors.amber;
    final label = !lockedOnSurface
        ? 'Aim at a corner'
        : (surfaceKind == 'ceiling' ? 'Ceiling — Add corner' : 'Floor — Add corner');

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: SizedBox(
              width: 72,
              height: 72,
              child: CustomPaint(
                painter: _ReticlePainter(
                  color: accent,
                  solid: lockedOnSurface,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$markCount / $recommendedMarks corners',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final Color color;
  final bool solid;

  _ReticlePainter({required this.color, required this.solid});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..color = color.withValues(alpha: solid ? 0.95 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = solid ? 2.4 : 1.6;
    final cross = Paint()
      ..color = color.withValues(alpha: solid ? 0.95 : 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color.withValues(alpha: solid ? 1 : 0.7);

    canvas.drawCircle(c, 22, ring);
    canvas.drawCircle(c, 3.5, dot);
    const arm = 10.0;
    const gap = 7.0;
    canvas.drawLine(Offset(c.dx, c.dy - gap - arm), Offset(c.dx, c.dy - gap), cross);
    canvas.drawLine(Offset(c.dx, c.dy + gap), Offset(c.dx, c.dy + gap + arm), cross);
    canvas.drawLine(Offset(c.dx - gap - arm, c.dy), Offset(c.dx - gap, c.dy), cross);
    canvas.drawLine(Offset(c.dx + gap, c.dy), Offset(c.dx + gap + arm, c.dy), cross);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.solid != solid;
}
