import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Touch magnifier bubble for precise Rig placement while dragging.
///
/// Uses a scaled duplicate of [scene] (not RawMagnifier/BackdropFilter) so it
/// works reliably on Android/Impeller where backdrop sampling often fails.
class RigDragMagnifier extends StatelessWidget {
  final Offset focalPoint;
  final Size canvasSize;
  final bool blocked;
  final Widget scene;

  const RigDragMagnifier({
    super.key,
    required this.focalPoint,
    required this.canvasSize,
    required this.blocked,
    required this.scene,
  });

  static const _diameter = 104.0;
  static const _scale = 2.35;
  static const _lift = 88.0;

  @override
  Widget build(BuildContext context) {
    final radius = _diameter * 0.5;
    final left = (focalPoint.dx - radius).clamp(6.0, canvasSize.width - _diameter - 6);
    final top = (focalPoint.dy - _lift - _diameter).clamp(6.0, canvasSize.height - _diameter - 6);
    final borderColor = blocked ? AppColors.red : AppColors.cyan;

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
                border: Border.all(color: borderColor, width: 1.5),
              ),
            ),
          ),
        ),
        Positioned(
          left: focalPoint.dx - 0.5,
          top: focalPoint.dy - _lift,
          child: IgnorePointer(
            child: Container(
              width: 1,
              height: _lift,
              color: borderColor.withValues(alpha: 0.55),
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
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: Offset(0, 4),
                    color: Colors.black45,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: canvasSize.width * _scale,
                    minHeight: canvasSize.height * _scale,
                    maxWidth: canvasSize.width * _scale,
                    maxHeight: canvasSize.height * _scale,
                    child: Transform.translate(
                      offset: Offset(
                        radius - focalPoint.dx * _scale,
                        radius - focalPoint.dy * _scale,
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
                  Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 1.5),
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
