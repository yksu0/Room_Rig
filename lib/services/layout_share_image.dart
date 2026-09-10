// lib/services/layout_share_image.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../widgets/bench_room_views.dart';

/// Renders a before/after floor-plan PNG and shares it via the OS sheet.
class LayoutShareImage {
  LayoutShareImage._();

  static Future<Uint8List> renderBeforeAfterPng({
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> before,
    required List<FurnitureItem> after,
    String beforeLabel = 'Before',
    String afterLabel = 'After',
    String? footer,
  }) async {
    const width = 720.0;
    const height = 420.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width, height);

    canvas.drawRect(bounds, Paint()..color = const Color(0xFF0E1218));

    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'Room Rig · layout compare',
        style: TextStyle(
          color: Color(0xFF8B9BB4),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 32);
    titlePainter.paint(canvas, const Offset(16, 14));

    const gap = 16.0;
    const sidePad = 16.0;
    const top = 44.0;
    const bottomPad = 36.0;
    final panelW = (width - sidePad * 2 - gap) / 2;
    final panelH = height - top - bottomPad;
    final leftRect = Rect.fromLTWH(sidePad, top, panelW, panelH);
    final rightRect = Rect.fromLTWH(sidePad + panelW + gap, top, panelW, panelH);

    _paintPanel(
      canvas: canvas,
      rect: leftRect,
      label: beforeLabel,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: before,
    );
    _paintPanel(
      canvas: canvas,
      rect: rightRect,
      label: afterLabel,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: after,
    );

    if (footer != null && footer.trim().isNotEmpty) {
      final foot = TextPainter(
        text: TextSpan(
          text: footer.trim(),
          style: const TextStyle(color: Color(0xFFB7C3D6), fontSize: 11, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: width - 32);
      foot.paint(canvas, Offset(16, height - 28));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }

  static void _paintPanel({
    required Canvas canvas,
    required Rect rect,
    required String label,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = AppColors.surface.withValues(alpha: 0.95),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.cyan,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 16);
    labelPainter.paint(canvas, rect.topLeft + const Offset(10, 8));

    final paintRect = Rect.fromLTWH(
      rect.left + 8,
      rect.top + 28,
      rect.width - 16,
      rect.height - 36,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(paintRect, const Radius.circular(10)));
    canvas.translate(paintRect.left, paintRect.top);
    BenchRoom2DPainter(
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: furniture,
    ).paint(canvas, paintRect.size);
    canvas.restore();
  }

  static Future<void> shareBeforeAfter({
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> before,
    required List<FurnitureItem> after,
    String beforeLabel = 'Before',
    String afterLabel = 'After',
    String? footer,
    String filename = 'room_rig_before_after.png',
  }) async {
    final png = await renderBeforeAfterPng(
      gridCols: gridCols,
      gridRows: gridRows,
      before: before,
      after: after,
      beforeLabel: beforeLabel,
      afterLabel: afterLabel,
      footer: footer,
    );
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsBytes(png, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: footer ?? 'Room Rig before / after layout',
      subject: 'Room Rig layout',
    );
  }
}
