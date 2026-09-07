import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Offset magnifier bubble — shows what's under the finger on the current canvas.
///
/// The bubble sits above the touch (so the finger doesn't cover it) and samples
/// the same 2D/3D view already on screen. Light zoom only; no separate camera.
class RigDragMagnifier extends StatelessWidget {
  final Offset pointerLocal;
  final Size canvasSize;
  final bool blocked;
  final Widget scene;

  const RigDragMagnifier({
    super.key,
    required this.pointerLocal,
    required this.canvasSize,
    required this.blocked,
    required this.scene,
  });

  static const _diameter = 104.0;
  /// Mild zoom so under-finger detail is readable without looking alien.
  static const _scale = 1.45;
  static const _lift = 88.0;

  @override
  Widget build(BuildContext context) {
    final radius = _diameter * 0.5;
    final left = (pointerLocal.dx - radius).clamp(6.0, canvasSize.width - _diameter - 6);
    final top =
        (pointerLocal.dy - _lift - _diameter).clamp(6.0, canvasSize.height - _diameter - 6);
    final borderColor = blocked ? AppColors.red : AppColors.cyan;
    final finger = pointerLocal;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: finger.dx - 4,
          top: finger.dy - 4,
          child: IgnorePointer(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: borderColor.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ),
        Positioned(
          left: finger.dx - 0.5,
          top: top + _diameter,
          child: IgnorePointer(
            child: Container(
              width: 1,
              height: (finger.dy - (top + _diameter)).clamp(0.0, _lift),
              color: borderColor.withValues(alpha: 0.45),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: Container(
              width: _diameter,
              height: _diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, 3),
                    color: Colors.black38,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(
                    radius - finger.dx * _scale,
                    radius - finger.dy * _scale,
                  ),
                  child: Transform.scale(
                    scale: _scale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: canvasSize.width,
                      height: canvasSize.height,
                      child: scene,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
