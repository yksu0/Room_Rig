import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class DetectedBox {
  final double left, top, width, height;
  final Color color;

  const DetectedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.color,
  });
}

Color colorForDetectionCategory(String category) {
  switch (category) {
    case 'airflow':
      return AppColors.airflowColor;
    case 'lighting':
      return AppColors.lightingColor;
    case 'ergonomics':
      return AppColors.ergonomicsColor;
    default:
      return AppColors.cyan;
  }
}

class DetectionOverlayPainter extends CustomPainter {
  final List<DetectedBox> boxes;

  const DetectionOverlayPainter({required this.boxes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final rect = Rect.fromLTWH(
        box.left * size.width,
        box.top * size.height,
        box.width * size.width,
        box.height * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = box.color.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = box.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter old) => old.boxes != boxes;
}

class ScanDetectionOverlay extends StatelessWidget {
  final List<DetectedBox> boxes;

  const ScanDetectionOverlay({super.key, required this.boxes});

  @override
  Widget build(BuildContext context) {
    if (boxes.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: DetectionOverlayPainter(boxes: List.unmodifiable(boxes)),
        );
      },
    );
  }
}
