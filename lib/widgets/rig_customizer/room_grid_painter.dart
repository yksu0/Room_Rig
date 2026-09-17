// lib/widgets/rig_customizer/room_grid_painter.dart
import 'package:flutter/material.dart';
import '../../models/room_scale.dart';
import '../../models/scan_layout_model.dart';
import '../../models/surface_mount.dart';
import '../../theme/app_theme.dart';
typedef Fitting2D = ({SurfaceMount mount, bool selected});

class RoomGridPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final Rect? roomRect;
  final CoverageGrid? coverage;
  final List<Fitting2D> fittings;
  final double lengthMeters;
  final double widthMeters;

  RoomGridPainter({
    required this.gridCols,
    required this.gridRows,
    this.roomRect,
    this.coverage,
    this.fittings = const [],
    this.lengthMeters = 0,
    this.widthMeters = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final room = roomRect ?? Rect.fromLTWH(0, 0, size.width, size.height);
    final cellW = room.width / gridCols;
    final cellH = room.height / gridRows;

    final cov = coverage;
    if (cov != null && cov.cols == gridCols && cov.rows == gridRows) {
      for (int row = 0; row < gridRows; row++) {
        for (int col = 0; col < gridCols; col++) {
          final v = cov.coverage[row * cov.cols + col].clamp(0.0, 1.0);
          if (v < 0.05) continue;
          final paint = Paint()
            ..color = AppColors.cyan.withValues(alpha: 0.08 + v * 0.18);
          canvas.drawRect(
            Rect.fromLTWH(
              room.left + col * cellW,
              room.top + row * cellH,
              cellW,
              cellH,
            ),
            paint,
          );
        }
      }
    }

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int col = 0; col <= gridCols; col++) {
      final x = room.left + col * cellW;
      canvas.drawLine(Offset(x, room.top), Offset(x, room.bottom), gridPaint);
    }
    for (int row = 0; row <= gridRows; row++) {
      final y = room.top + row * cellH;
      canvas.drawLine(Offset(room.left, y), Offset(room.right, y), gridPaint);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(room.deflate(1.5), const Radius.circular(4)),
      Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.38)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    _paintDimensionLabels(canvas, room);
  }

  void _paintDimensionLabels(Canvas canvas, Rect room) {
    final length = lengthMeters > 0 ? lengthMeters : RoomScale.metersFromCells(gridCols);
    final width = widthMeters > 0 ? widthMeters : RoomScale.metersFromCells(gridRows);
    final style = const TextStyle(color: Color(0xFF8B93B8), fontSize: 10, fontWeight: FontWeight.w700);
    final top = TextPainter(
      text: TextSpan(text: RoomScale.formatMeters(length), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    top.paint(canvas, Offset(room.left + (room.width - top.width) / 2, room.top + 4));
    final side = TextPainter(
      text: TextSpan(text: RoomScale.formatMeters(width), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(room.left + 4, room.top + (room.height + side.width) / 2);
    canvas.rotate(-1.5708);
    side.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RoomGridPainter old) =>
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.roomRect != roomRect ||
      old.coverage != coverage ||
      old.fittings != fittings ||
      old.lengthMeters != lengthMeters ||
      old.widthMeters != widthMeters;
}
