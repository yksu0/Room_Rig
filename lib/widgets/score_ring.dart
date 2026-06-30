// lib/widgets/score_ring.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScoreRing extends StatefulWidget {
  final double score;
  final double size;
  final Color color;
  final String label;
  final bool animate;

  const ScoreRing({
    super.key,
    required this.score,
    required this.size,
    required this.color,
    required this.label,
    this.animate = true,
  });

  @override
  State<ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<ScoreRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: widget.score / 100)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.animate) _controller.forward();
  }

  @override
  void didUpdateWidget(ScoreRing old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _animation = Tween<double>(begin: _animation.value, end: widget.score / 100)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: _animation.value,
            color: widget.color,
            bgColor: AppColors.border,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(widget.score * _animation.value / widget.score * widget.score).round()}',
                  style: TextStyle(
                    color: widget.color,
                    fontSize: widget.size * 0.22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: widget.size * 0.1,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;

  _RingPainter({required this.progress, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    final strokeWidth = size.width * 0.08;

    final bgPaint = Paint()
      ..color = bgColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [color.withValues(alpha: 0.6), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fgPaint,
    );

    // Glow dot at end
    if (progress > 0.01) {
      final angle = -pi / 2 + 2 * pi * progress;
      final dotPos = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawCircle(
        dotPos,
        strokeWidth / 2 + 2,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(dotPos, strokeWidth / 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
