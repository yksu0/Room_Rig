// lib/widgets/bench_room_views.dart
// Rig-style 2D / 3D room previews for the benchmark prototype.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';

Color categoryColor(String cat) {
  switch (cat) {
    case 'airflow':
      return AppColors.airflowColor;
    case 'lighting':
      return AppColors.lightingColor;
    case 'ergonomics':
      return AppColors.ergonomicsColor;
    default:
      return AppColors.textMuted;
  }
}

String shortFurnitureLabel(FurnitureItem item) {
  switch (item.id) {
    case 'ac':
      return 'AC';
    case 'pc':
      return 'PC';
    case 'window':
      return 'WIN';
    case 'door':
      return 'DOOR';
    case 'desk':
      return 'DESK';
    case 'chair':
      return 'SEAT';
    case 'bed':
      return 'BED';
    case 'shelf':
    case 'bookshelf':
      return 'SHELF';
    case 'lamp':
      return 'LAMP';
    case 'fan':
      return 'FAN';
    default:
      final n = item.name.toUpperCase();
      return n.length <= 5 ? n : n.substring(0, 4);
  }
}

/// Shared 2D room rect (aspect-correct) + furniture hit testing for Bench demos.
class BenchRoom2DGeometry {
  static const legendW = 86.0;
  static const pad = 10.0;

  static Rect roomRectFor({
    required Size size,
    required int gridCols,
    required int gridRows,
  }) {
    final availW = (size.width - legendW - pad * 2 - 8).clamp(40.0, size.width);
    final availH = (size.height - pad * 2).clamp(40.0, size.height);
    final aspect = gridCols <= 0 || gridRows <= 0 ? 1.0 : gridCols / gridRows;
    late final double roomW;
    late final double roomH;
    if (availW / availH > aspect) {
      roomH = availH;
      roomW = roomH * aspect;
    } else {
      roomW = availW;
      roomH = roomW / aspect;
    }
    return Rect.fromLTWH(
      pad + (availW - roomW) / 2,
      pad + (availH - roomH) / 2,
      roomW,
      roomH,
    );
  }

  /// Smallest item under the tap wins (so tiny AC/PC stay selectable over a bed).
  static FurnitureItem? hitTest({
    required Offset local,
    required Size size,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    if (gridCols <= 0 || gridRows <= 0) return null;
    final roomRect = roomRectFor(size: size, gridCols: gridCols, gridRows: gridRows);
    if (!roomRect.contains(local)) return null;

    final cellW = roomRect.width / gridCols;
    final cellH = roomRect.height / gridRows;
    final ordered = [...furniture]
      ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));

    for (final item in ordered) {
      final rect = Rect.fromLTWH(
        roomRect.left + item.gridX * cellW,
        roomRect.top + item.gridY * cellH,
        item.width * cellW,
        item.height * cellH,
      );
      if (rect.inflate(2).contains(local)) return item;
    }
    return null;
  }
}

/// One-line demo copy when tapping an item in Bench 2D.
String benchInspectBlurb(FurnitureItem item, {required String mode}) {
  final id = item.id.toLowerCase();
  switch (mode) {
    case 'lighting':
      if (id.contains('window')) return 'Primary daylight source — keep the path to the desk clear.';
      if (id.contains('lamp')) return 'Task light — place near the desk, not behind blockers.';
      if (id.contains('desk')) return 'Task zone — needs daylight + lamp without shelf shadows.';
      if (id.contains('shelf') || id.contains('book')) return 'Tall storage can cast shadows into the work area.';
      return '${item.name} — lighting impact in this layout.';
    case 'ergonomics':
      if (id.contains('desk')) return 'Primary work surface — chair should sit in reach of this desk.';
      if (id.contains('chair')) return 'Seating — keep clearance behind and a clear path to the desk.';
      if (id.contains('door')) return 'Entry — leave an approach aisle so you can walk in comfortably.';
      if (id.contains('monitor')) return 'Screen height / reach — belongs on the desk zone.';
      return '${item.name} — ergonomics clearance in this layout.';
    case 'airflow':
    default:
      if (id.contains('ac')) return 'Cold supply — mid-wall placement covers far more floor than a corner.';
      if (id.contains('fan')) return 'Circulation assist — aims into open floor, not into a cluttered corner.';
      if (id.contains('pc')) return 'Heat source — better inside the cooled sweep so exhaust mixes with supply.';
      if (id.contains('bed')) return 'Large blocker — keep on the perimeter, out of the AC throw cone.';
      if (id.contains('shelf') || id.contains('book')) return 'Blocks residual airflow — better in a dead corner.';
      if (id.contains('window')) return 'Return / exhaust opening — offset from the AC throw axis.';
      if (id.contains('door')) return 'Entry opening — keep the approach path clear of clutter.';
      return '${item.name} — airflow role in this layout.';
  }
}

class BenchRoom2DPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final List<FurnitureItem> furniture;
  final String? highlightNote;
  final bool showCoverageCone;
  final String? selectedId;

  BenchRoom2DPainter({
    required this.gridCols,
    required this.gridRows,
    required this.furniture,
    this.highlightNote,
    this.showCoverageCone = true,
    this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final roomRect = BenchRoom2DGeometry.roomRectFor(
      size: size,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(12)),
      Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(12)),
      Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final cellW = roomRect.width / gridCols;
    final cellH = roomRect.height / gridRows;
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
      ..strokeWidth = 0.55;
    for (int c = 1; c < gridCols; c++) {
      final dx = roomRect.left + cellW * c;
      canvas.drawLine(Offset(dx, roomRect.top), Offset(dx, roomRect.bottom), gridPaint);
    }
    for (int r = 1; r < gridRows; r++) {
      final dy = roomRect.top + cellH * r;
      canvas.drawLine(Offset(roomRect.left, dy), Offset(roomRect.right, dy), gridPaint);
    }

    FurnitureItem? ac;
    for (final f in furniture) {
      if (f.id.toLowerCase().contains('ac')) ac = f;
    }

    // Soft coverage cone from AC (into the room) — shows "max coverage" intent.
    if (showCoverageCone && ac != null) {
      final origin = Offset(
        roomRect.left + (ac.gridX + ac.width / 2) * cellW,
        roomRect.top + (ac.gridY + ac.height / 2) * cellH,
      );
      // Blow toward room center from the AC wall.
      final towardCenter = Offset(roomRect.center.dx - origin.dx, roomRect.center.dy - origin.dy);
      final angle = math.atan2(towardCenter.dy, towardCenter.dx);
      final reach = math.min(roomRect.width, roomRect.height) * 0.92;
      final sweep = 1.15; // radians ~66°

      final path = Path()..moveTo(origin.dx, origin.dy);
      path.arcTo(
        Rect.fromCircle(center: origin, radius: reach),
        angle - sweep / 2,
        sweep,
        false,
      );
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = AppColors.cyan.withValues(alpha: 0.10),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    // Draw larger items first so small ones stay readable on top.
    final ordered = [...furniture]..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));

    for (final item in ordered) {
      final selected = selectedId != null && item.id == selectedId;
      final x = roomRect.left + item.gridX * cellW;
      final y = roomRect.top + item.gridY * cellH;
      final w = item.width * cellW;
      final h = item.height * cellH;
      final color = categoryColor(item.category);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 3, y + 3, (w - 6).clamp(8, roomRect.width), (h - 6).clamp(8, roomRect.height)),
        const Radius.circular(7),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: selected ? 0.38 : 0.22));
      if (selected) {
        canvas.drawRRect(
          rect.inflate(2),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: selected ? 1.0 : 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.2 : 1.4,
      );

      // Short code only — full names live in the side legend.
      final label = shortFurnitureLabel(item);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: (w - 6).clamp(16, 80));
      tp.paint(
        canvas,
        Offset(
          x + (w - tp.width) / 2,
          y + (h - tp.height) / 2,
        ),
      );
    }

    _paintLegend(canvas, size, roomRect);
  }

  void _paintLegend(Canvas canvas, Size size, Rect roomRect) {
    final left = roomRect.right + 10;
    var top = roomRect.top;
    final title = TextPainter(
      text: const TextSpan(
        text: 'ITEMS',
        style: TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(left, top));
    top += 16;

    for (final item in furniture) {
      final color = categoryColor(item.category);
      canvas.drawCircle(Offset(left + 5, top + 6), 4, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: '${shortFurnitureLabel(item)}  ${item.name}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width - left - 8);
      tp.paint(canvas, Offset(left + 14, top));
      top += 16;
      if (top > roomRect.bottom - 8) break;
    }

    // Tiny coverage key.
    top = roomRect.bottom - 28;
    canvas.drawCircle(Offset(left + 5, top + 6), 4, Paint()..color = AppColors.cyan.withValues(alpha: 0.5));
    final tip = TextPainter(
      text: const TextSpan(
        text: 'AC throw\ncoverage',
        style: TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w600, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 70);
    tip.paint(canvas, Offset(left + 14, top));
  }

  @override
  bool shouldRepaint(covariant BenchRoom2DPainter old) =>
      old.furniture != furniture ||
      old.highlightNote != highlightNote ||
      old.showCoverageCone != showCoverageCone ||
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.selectedId != selectedId;
}

class BenchRoom3DPainter extends CustomPainter {
  final double roomWidth;
  final double roomDepth;
  final double roomHeight;
  final int gridCols;
  final int gridRows;
  final double yaw;
  final double pitch;
  final double distance;
  final List<FurnitureItem> furniture;

  BenchRoom3DPainter({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.gridCols,
    required this.gridRows,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.furniture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
    );

    final faces = <_Face>[];
    final v000 = const _V3(0, 0, 0);
    final v100 = _V3(roomWidth, 0, 0);
    final v110 = _V3(roomWidth, 0, roomDepth);
    final v010 = _V3(0, 0, roomDepth);
    final v001 = _V3(0, roomHeight, 0);
    final v101 = _V3(roomWidth, roomHeight, 0);
    final v111 = _V3(roomWidth, roomHeight, roomDepth);
    final v011 = _V3(0, roomHeight, roomDepth);

    faces.add(_Face([v000, v100, v110, v010], AppColors.surfaceAlt.withValues(alpha: 0.72)));
    faces.add(_Face([v001, v011, v111, v101], AppColors.textMuted.withValues(alpha: 0.22)));
    faces.add(_Face([v000, v001, v101, v100], AppColors.surfaceAlt.withValues(alpha: 0.40)));
    faces.add(_Face([v100, v101, v111, v110], AppColors.surfaceAlt.withValues(alpha: 0.44)));
    faces.add(_Face([v110, v111, v011, v010], AppColors.surfaceAlt.withValues(alpha: 0.50)));
    faces.add(_Face([v010, v011, v001, v000], AppColors.surfaceAlt.withValues(alpha: 0.42)));

    final projected = <_PFace>[];
    for (final face in faces) {
      final p = _projectFace(face, size, cam);
      if (p != null) projected.add(p);
    }
    projected.sort((a, b) => b.depth.compareTo(a.depth));
    for (final pFace in projected) {
      final path = Path()..addPolygon(pFace.points, true);
      canvas.drawPath(path, Paint()..color = pFace.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (int c = 0; c <= gridCols; c++) {
      final a = _project(_V3(c.toDouble(), 0.001, 0), size, cam);
      final b = _project(_V3(c.toDouble(), 0.001, roomDepth), size, cam);
      if (a != null && b != null) canvas.drawLine(a.$1, b.$1, gridPaint);
    }
    for (int r = 0; r <= gridRows; r++) {
      final a = _project(_V3(0, 0.001, r.toDouble()), size, cam);
      final b = _project(_V3(roomWidth, 0.001, r.toDouble()), size, cam);
      if (a != null && b != null) canvas.drawLine(a.$1, b.$1, gridPaint);
    }

    final furnitureFaces = <_PFace>[];
    for (final item in furniture) {
      final color = categoryColor(item.category);
      final yTop = (0.55 + item.ergonomicsImpact.abs() * 0.5 + item.height * 0.12).clamp(0.45, 1.85);
      final x = item.gridX;
      final z = item.gridY;
      final w = item.width;
      final d = item.height;
      final a = _V3(x, 0, z);
      final b = _V3(x + w, 0, z);
      final c = _V3(x + w, 0, z + d);
      final e = _V3(x, 0, z + d);
      final a2 = _V3(x, yTop, z);
      final b2 = _V3(x + w, yTop, z);
      final c2 = _V3(x + w, yTop, z + d);
      final e2 = _V3(x, yTop, z + d);

      void addFace(List<_V3> verts, double alpha) {
        final pf = _projectFace(_Face(verts, color.withValues(alpha: alpha)), size, cam);
        if (pf != null) furnitureFaces.add(pf);
      }

      addFace([a2, b2, c2, e2], 0.55);
      addFace([a, b, b2, a2], 0.40);
      addFace([b, c, c2, b2], 0.46);
      addFace([c, e, e2, c2], 0.42);
      addFace([e, a, a2, e2], 0.38);
    }

    furnitureFaces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final f in furnitureFaces) {
      final path = Path()..addPolygon(f.points, true);
      canvas.drawPath(path, Paint()..color = f.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    // Hint that the view is orbitable.
    final hint = TextPainter(
      text: const TextSpan(
        text: 'Drag to orbit · double-tap reset · scroll to zoom',
        style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hint.paint(canvas, Offset(12, size.height - hint.height - 10));
  }

  @override
  bool shouldRepaint(covariant BenchRoom3DPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.distance != distance ||
      old.furniture != furniture;

  @override
  bool? hitTest(Offset position) => true;
}

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
}

class _Cam {
  final double roomWidth, roomDepth, roomHeight, yaw, pitch, distance;
  _Cam({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.yaw,
    required this.pitch,
    required this.distance,
  });
}

class _Face {
  final List<_V3> vertices;
  final Color color;
  _Face(this.vertices, this.color);
}

class _PFace {
  final List<Offset> points;
  final double depth;
  final Color color;
  _PFace({required this.points, required this.depth, required this.color});
}

_V3 _cross(_V3 a, _V3 b) =>
    _V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

double _dot(_V3 a, _V3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

_V3 _normalize(_V3 v) {
  final m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (m <= 0.0001) return const _V3(0, 0, 1);
  return _V3(v.x / m, v.y / m, v.z / m);
}

(Offset, double)? _project(_V3 p, Size size, _Cam cam) {
  final center = _V3(cam.roomWidth * 0.5, cam.roomHeight * 0.45, cam.roomDepth * 0.5);
  final horizontal = cam.distance * math.cos(cam.pitch);
  final eye = _V3(
    center.x + horizontal * math.sin(cam.yaw),
    center.y + cam.distance * math.sin(cam.pitch),
    center.z + horizontal * math.cos(cam.yaw),
  );
  final forward = _normalize(center - eye);
  final right = _normalize(_cross(forward, const _V3(0, 1, 0)));
  final up = _normalize(_cross(right, forward));
  final rel = p - eye;
  final cx = _dot(rel, right);
  final cy = _dot(rel, up);
  final cz = _dot(rel, forward);
  if (cz <= 0.06) return null;
  const fov = 55 * math.pi / 180;
  final focal = (size.width * 0.5) / math.tan(fov * 0.5);
  return (Offset(size.width * 0.5 + (cx / cz) * focal, size.height * 0.58 - (cy / cz) * focal), cz);
}

_PFace? _projectFace(_Face face, Size size, _Cam cam) {
  final points = <Offset>[];
  double depth = 0;
  for (final v in face.vertices) {
    final p = _project(v, size, cam);
    if (p == null) return null;
    points.add(p.$1);
    depth += p.$2;
  }
  return _PFace(points: points, depth: depth / face.vertices.length, color: face.color);
}
