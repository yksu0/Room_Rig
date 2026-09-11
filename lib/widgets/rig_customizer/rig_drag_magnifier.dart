import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Offset loupe for Rig drag — samples the live 2D/3D canvas under [focalPoint].
///
/// Must lay the [scene] out at full [canvasSize] (via [OverflowBox]). Clipping the
/// bubble to ~104px without that step shrinks the scene first, so scale/translate
/// math zooms nonsense instead of the current orbit / floor plan.
class RigDragMagnifier extends StatelessWidget {
  final Offset pointerLocal;
  final Offset focalPoint;
  final Size canvasSize;
  final bool blocked;
  final Widget scene;

  const RigDragMagnifier({
    super.key,
    required this.pointerLocal,
    required this.focalPoint,
    required this.canvasSize,
    required this.blocked,
    required this.scene,
  });

  static const diameter = 124.0;
  /// Mild zoom — enough to place precisely without feeling glued to the item.
  static const scale = 1.35;
  /// Keep the bubble clearly above the finger.
  static const lift = 140.0;
  static const edgePad = 6.0;

  /// Maps [focal] to the bubble center after magnification.
  static Matrix4 sampleTransform({
    required Offset focal,
    required double diameter,
    required double scale,
  }) {
    final r = diameter * 0.5;
    return Matrix4.identity()
      ..translateByDouble(r, r, 0, 1)
      ..scaleByDouble(scale, scale, 1.0, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  /// Bubble top-left; prefers above the finger, then side / below near edges.
  static Offset bubbleOrigin({
    required Offset pointer,
    required Size canvas,
    double diameter = RigDragMagnifier.diameter,
    double lift = RigDragMagnifier.lift,
    double pad = RigDragMagnifier.edgePad,
  }) {
    final maxLeft = (canvas.width - diameter - pad).clamp(pad, double.infinity);
    final maxTop = (canvas.height - diameter - pad).clamp(pad, double.infinity);
    var left = (pointer.dx - diameter * 0.5).clamp(pad, maxLeft);
    var top = pointer.dy - lift - diameter;

    if (top < pad) {
      // Prefer a side loupe when there is no room above.
      final rightSlot = pointer.dx + 28;
      final leftSlot = pointer.dx - diameter - 28;
      if (rightSlot + diameter <= canvas.width - pad) {
        left = rightSlot.clamp(pad, maxLeft);
        top = (pointer.dy - diameter * 0.5).clamp(pad, maxTop);
      } else if (leftSlot >= pad) {
        left = leftSlot.clamp(pad, maxLeft);
        top = (pointer.dy - diameter * 0.5).clamp(pad, maxTop);
      } else {
        top = (pointer.dy + 28).clamp(pad, maxTop);
        left = (pointer.dx - diameter * 0.5).clamp(pad, maxLeft);
      }
    } else {
      top = top.clamp(pad, maxTop);
    }
    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final origin = bubbleOrigin(pointer: pointerLocal, canvas: canvasSize);
    final borderColor = blocked ? AppColors.red : AppColors.cyan;
    final stemTop = origin.dy + diameter;
    final stemHeight = (pointerLocal.dy - stemTop).clamp(0.0, lift + 40);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: focalPoint.dx - 5,
          top: focalPoint.dy - 5,
          child: IgnorePointer(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: borderColor.withValues(alpha: 0.35),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
            ),
          ),
        ),
        if (stemHeight > 2)
          Positioned(
            left: pointerLocal.dx - 0.5,
            top: stemTop,
            child: IgnorePointer(
              child: Container(
                width: 1,
                height: stemHeight,
                color: borderColor.withValues(alpha: 0.45),
              ),
            ),
          ),
        Positioned(
          left: origin.dx,
          top: origin.dy,
          child: IgnorePointer(
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 10,
                    offset: Offset(0, 3),
                    color: Colors.black45,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipOval(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: canvasSize.width,
                      maxWidth: canvasSize.width,
                      minHeight: canvasSize.height,
                      maxHeight: canvasSize.height,
                      child: Transform(
                        alignment: Alignment.topLeft,
                        transform: sampleTransform(
                          focal: focalPoint,
                          diameter: diameter,
                          scale: scale,
                        ),
                        child: SizedBox(
                          width: canvasSize.width,
                          height: canvasSize.height,
                          child: scene,
                        ),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _LoupeCrosshairPainter(color: borderColor),
                  ),
                  // Soft vignette so the sample reads as a lens, not a hard crop.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.22),
                          ],
                          stops: const [0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: borderColor.withValues(alpha: 0.85),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoupeCrosshairPainter extends CustomPainter {
  final Color color;

  _LoupeCrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    const arm = 14.0;
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), paint);
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), paint);
  }

  @override
  bool shouldRepaint(covariant _LoupeCrosshairPainter oldDelegate) =>
      oldDelegate.color != color;
}
