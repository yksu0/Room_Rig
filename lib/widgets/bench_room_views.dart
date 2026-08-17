// lib/widgets/bench_room_views.dart
// Rig-style 2D / 3D room previews for the benchmark prototype.
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'room_orbit_projection.dart';
import 'room_plan_geometry.dart';
import '../theme/app_theme.dart';
import 'furniture_shapes.dart';

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
  final id = item.id.toLowerCase();
  if (id == 'ac' || id.startsWith('ac_')) return 'AC';
  if (id.contains('portable_ac')) return 'PAC';
  if (id.contains('evaporative')) return 'COOL';
  if (id == 'pc' || id.startsWith('pc_')) return 'PC';
  if (id.contains('nas') || id.contains('server')) return 'NAS';
  if (id.contains('console')) return 'GAME';
  if (id.contains('heater')) return 'HEAT';
  if (id.contains('radiator')) return 'RAD';
  if (id.contains('fridge')) return 'FRDG';
  if (id.contains('desk_fan')) return 'DFAN';
  switch (item.id) {
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
    bool reserveLegend = false,
  }) {
    return RoomPlanGeometry.roomRectFor(
      size: size,
      gridCols: gridCols,
      gridRows: gridRows,
      pad: pad,
      horizontalReserve: reserveLegend ? legendW + 8 : 0,
    );
  }

  /// Aspect-correct rect for sim field painters (no side legend gutter).
  static Rect fieldRectFor({
    required Size size,
    required int gridCols,
    required int gridRows,
    double pad = 12,
  }) {
    return RoomPlanGeometry.roomRectFor(
      size: size,
      gridCols: gridCols,
      gridRows: gridRows,
      pad: pad,
      horizontalReserve: 0,
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
    return RoomPlanGeometry.hitTestFloor(
      local: local,
      roomRect: roomRect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: furniture,
    );
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
      if (id.contains('intake')) return 'Outdoor-air supply — pressurizes the room so windows leak out.';
      if (id.contains('exhaust')) return 'Extract fan — pulls room air out so windows leak in to replace it.';
      if (id.contains('ac')) return 'Cold supply — recirculates indoor air. Does not push air out the window.';
      if (id.contains('fan')) return 'Circulation assist — aims into open floor, not into a cluttered corner.';
      if (id.contains('pc')) return 'Heat source — better inside the cooled sweep so exhaust mixes with supply.';
      if (id.contains('bed')) return 'Large blocker — keep on the perimeter, out of the AC throw cone.';
      if (id.contains('shelf') || id.contains('book')) return 'Blocks residual airflow — better in a dead corner.';
      if (id.contains('window')) return 'Passive gap — seeps a fraction of any intake/exhaust mismatch, like a PC case slot.';
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
  final bool showLegend;

  BenchRoom2DPainter({
    required this.gridCols,
    required this.gridRows,
    required this.furniture,
    this.highlightNote,
    this.showCoverageCone = true,
    this.selectedId,
    this.showLegend = false,
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
      if (SurfaceMounts.isVent(f)) ac = f;
    }

    // Soft coverage cone from AC (into the room) — shows "max coverage" intent.
    if (showCoverageCone && ac != null) {
      final mount = SurfaceMounts.of(ac, gridCols: gridCols, gridRows: gridRows);
      final span = mount.span;
      final origin = span != null
          ? Offset(
              roomRect.left + ((span.x0 + span.x1) / 2) * cellW + span.inwardX * cellW * 0.35,
              roomRect.top + ((span.z0 + span.z1) / 2) * cellH + span.inwardZ * cellH * 0.35,
            )
          : Offset(
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

    BenchFurnitureRenderer.paint2D(
      canvas,
      roomRect: roomRect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: furniture,
      selectedId: selectedId,
    );

    if (showLegend) {
      _paintLegend(canvas, size, roomRect);
    }
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
      old.showLegend != showLegend ||
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
  final double? lookAtX;
  final double? lookAtZ;
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
    this.lookAtX,
    this.lookAtZ,
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
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
    );

    BenchFurnitureRenderer.paintRoomWireframe(
      canvas,
      size,
      cam,
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    BenchFurnitureRenderer.paint3D(
      canvas,
      size,
      cam,
      gridCols: gridCols,
      gridRows: gridRows,
      roomHeight: roomHeight,
      furniture: furniture,
    );

    // Hint that the view is orbitable.
    final hint = TextPainter(
      text: const TextSpan(
        text: '1 finger orbit · 2 fingers pan + pinch · double-tap reset',
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
      old.lookAtX != lookAtX ||
      old.lookAtZ != lookAtZ ||
      old.furniture != furniture;

  @override
  bool? hitTest(Offset position) => true;
}

class _BenchOverlay {
  final double depth;
  final void Function(Canvas canvas) paint;
  _BenchOverlay(this.depth, this.paint);
}

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
}

class _Cam {
  final double roomWidth, roomDepth, roomHeight, yaw, pitch, distance;
  final double? lookAtX, lookAtZ;
  _Cam({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.lookAtX,
    this.lookAtZ,
  });

  double get pivotX => lookAtX ?? roomWidth * 0.5;
  double get pivotZ => lookAtZ ?? roomDepth * 0.5;
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
  final center = _V3(cam.pivotX, cam.roomHeight * 0.45, cam.pivotZ);
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

/// Rig-style furniture silhouettes for all Bench 2D/3D views.
class BenchFurnitureRenderer {
  BenchFurnitureRenderer._();

  static void paint2D(
    Canvas canvas, {
    required Rect roomRect,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
    String? selectedId,
  }) {
    final cellW = roomRect.width / gridCols;
    final cellH = roomRect.height / gridRows;
    final ordered = [...furniture]..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final wallItems = <FurnitureItem>[];
    final ceilingItems = <FurnitureItem>[];

    for (final item in ordered) {
      final mount = SurfaceMounts.of(
        item,
        gridCols: gridCols,
        gridRows: gridRows,
        furniture: furniture,
      );
      if (mount.isWall && mount.span != null) {
        wallItems.add(item);
        continue;
      }
      if (mount.isCeiling) {
        ceilingItems.add(item);
        continue;
      }

      final selected = selectedId != null && item.id == selectedId;
      final x = roomRect.left + item.gridX * cellW;
      final y = roomRect.top + item.gridY * cellH;
      final w = item.width * cellW;
      final h = item.height * cellH;
      final color = categoryColor(item.category);
      final cell = Rect.fromLTWH(
        x + 3,
        y + 3,
        (w - 6).clamp(8, roomRect.width),
        (h - 6).clamp(8, roomRect.height),
      );
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell.inflate(2), const Radius.circular(7)),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
      canvas.save();
      canvas.translate(cell.left, cell.top);
      FurnitureShapes.paintPlan(
        canvas,
        cell.size,
        FurnitureShapes.kindOf(item),
        color,
        selected: selected,
        yawDegrees: item.yawDegrees,
      );
      canvas.restore();

      if (!FurnitureShapes.showsFacing(FurnitureShapes.kindOf(item))) continue;
      final cx = x + w * 0.5;
      final cy = y + h * 0.5;
      final rad = item.yawDegrees * math.pi / 180.0;
      final dirX = math.sin(rad);
      final dirY = math.cos(rad);
      final reach = math.min(w, h) * 0.42;
      final tip = Offset(cx + dirX * reach, cy + dirY * reach);
      final back = Offset(cx + dirX * reach * 0.12, cy + dirY * reach * 0.12);
      final px = -dirY;
      final py = dirX;
      final left = Offset(back.dx + px * reach * 0.32, back.dy + py * reach * 0.32);
      final right = Offset(back.dx - px * reach * 0.32, back.dy - py * reach * 0.32);
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()..color = (selected ? Colors.white : color).withValues(alpha: 0.95),
      );
    }

    for (final item in ceilingItems) {
      _paintCeilingFixture2D(canvas, roomRect, cellW, cellH, item, selectedId == item.id);
    }
    for (final item in wallItems) {
      _paintWallFitting2D(
        canvas,
        roomRect,
        cellW,
        cellH,
        gridCols,
        gridRows,
        item,
        selectedId == item.id,
      );
    }
  }

  /// Open wireframe shell — interior stays visible (matches Lighting bench).
  static void paintRoomWireframe(
    Canvas canvas,
    Size size,
    _Cam cam, {
    required double roomWidth,
    required double roomDepth,
    required int gridCols,
    required int gridRows,
  }) {
    final corners = [
      const _V3(0, 0, 0),
      _V3(roomWidth, 0, 0),
      _V3(roomWidth, 0, roomDepth),
      _V3(0, 0, roomDepth),
      _V3(0, cam.roomHeight, 0),
      _V3(roomWidth, cam.roomHeight, 0),
      _V3(roomWidth, cam.roomHeight, roomDepth),
      _V3(0, cam.roomHeight, roomDepth),
    ];
    final projected = corners.map((v) => _project(v, size, cam)).toList();
    final edge = Paint()
      ..color = AppColors.border.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    void line(int a, int b) {
      final pa = projected[a];
      final pb = projected[b];
      if (pa == null || pb == null) return;
      canvas.drawLine(pa.$1, pb.$1, edge);
    }

    line(0, 1);
    line(1, 2);
    line(2, 3);
    line(3, 0);
    line(4, 5);
    line(5, 6);
    line(6, 7);
    line(7, 4);
    line(0, 4);
    line(1, 5);
    line(2, 6);
    line(3, 7);

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
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
  }

  static void paint3D(
    Canvas canvas,
    Size size,
    _Cam cam, {
    required int gridCols,
    required int gridRows,
    required double roomHeight,
    required List<FurnitureItem> furniture,
  }) {
    final furnitureFaces = <_PFace>[];
    final overlays = <_BenchOverlay>[];

    for (final item in furniture) {
      final mount = SurfaceMounts.of(
        item,
        gridCols: gridCols,
        gridRows: gridRows,
        roomHeight: roomHeight,
        furniture: furniture,
      );

      if (mount.isWall && mount.span != null) {
        _addWallFitting3D(furnitureFaces, overlays, item, mount, size, cam);
        continue;
      }
      if (mount.isCeiling) {
        _addCeilingFixture3D(overlays, item, mount, size, cam);
        continue;
      }

      final color = categoryColor(item.category);
      final kind = FurnitureShapes.kindOf(item);
      final yBase = mount.isDesk ? mount.bottomY : 0.0;
      for (final face in FurnitureShapes.facesFor(
        FurnitureShapes.boxes(
          kind: kind,
          x: item.gridX,
          z: item.gridY,
          width: item.width,
          depth: item.height,
          color: color,
          yBase: yBase,
          yawDegrees: item.yawDegrees,
        ),
      )) {
        final pf = _projectFace(
          _Face(
            [for (final v in face.vertices) _V3(v.x, v.y, v.z)],
            face.color,
          ),
          size,
          cam,
        );
        if (pf != null) furnitureFaces.add(pf);
      }

      if (!FurnitureShapes.showsFacing(kind)) continue;

      final yChev = yBase + 0.02;
      final cx = item.gridX + item.width * 0.5;
      final cz = item.gridY + item.height * 0.5;
      final rad = item.yawDegrees * math.pi / 180.0;
      final dirX = math.sin(rad);
      final dirZ = math.cos(rad);
      final reach = math.max(item.width, item.height) * 0.55 + 0.2;
      final tip = _project(_V3(cx + dirX * reach, yChev, cz + dirZ * reach), size, cam);
      final backX = cx + dirX * reach * 0.35;
      final backZ = cz + dirZ * reach * 0.35;
      final px = -dirZ;
      final pz = dirX;
      final left = _project(_V3(backX + px * 0.16, yChev, backZ + pz * 0.16), size, cam);
      final right = _project(_V3(backX - px * 0.16, yChev, backZ - pz * 0.16), size, cam);
      if (tip != null && left != null && right != null) {
        overlays.add(_BenchOverlay(tip.$2 - 0.01, (c) {
          final path = Path()
            ..moveTo(tip.$1.dx, tip.$1.dy)
            ..lineTo(left.$1.dx, left.$1.dy)
            ..lineTo(right.$1.dx, right.$1.dy)
            ..close();
          c.drawPath(path, Paint()..color = color.withValues(alpha: 0.9));
        }));
      }
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

    overlays.sort((a, b) => b.depth.compareTo(a.depth));
    for (final o in overlays) {
      o.paint(canvas);
    }
  }

  static void _paintWallFitting2D(
    Canvas canvas,
    Rect roomRect,
    double cellW,
    double cellH,
    int gridCols,
    int gridRows,
    FurnitureItem item,
    bool selected,
  ) {
    final mount = SurfaceMounts.of(item, gridCols: gridCols, gridRows: gridRows);
    final span = mount.span!;
    final color = switch (mount.style) {
      MountStyle.window => AppColors.lightingColor,
      MountStyle.vent => AppColors.airflowColor,
      MountStyle.intake => AppColors.green,
      MountStyle.exhaust => AppColors.orange,
      MountStyle.door => AppColors.textSecondary,
      _ => categoryColor(item.category),
    };

    late Rect band;
    switch (span.wall) {
      case RoomWall.north:
        band = Rect.fromLTRB(
          roomRect.left + span.x0 * cellW,
          roomRect.top,
          roomRect.left + span.x1 * cellW,
          roomRect.top + 14,
        );
      case RoomWall.south:
        band = Rect.fromLTRB(
          roomRect.left + span.x0 * cellW,
          roomRect.bottom - 14,
          roomRect.left + span.x1 * cellW,
          roomRect.bottom,
        );
      case RoomWall.west:
        band = Rect.fromLTRB(
          roomRect.left,
          roomRect.top + span.z0 * cellH,
          roomRect.left + 14,
          roomRect.top + span.z1 * cellH,
        );
      case RoomWall.east:
        band = Rect.fromLTRB(
          roomRect.right - 14,
          roomRect.top + span.z0 * cellH,
          roomRect.right,
          roomRect.top + span.z1 * cellH,
        );
    }

    final rrect = RRect.fromRectAndRadius(band, const Radius.circular(4));
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: selected ? 0.45 : 0.28));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: selected ? 1.0 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.4,
    );

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.1;
    if (mount.style == MountStyle.window) {
      canvas.drawLine(
        Offset(band.center.dx, band.top + 2),
        Offset(band.center.dx, band.bottom - 2),
        stroke,
      );
      canvas.drawLine(
        Offset(band.left + 2, band.center.dy),
        Offset(band.right - 2, band.center.dy),
        stroke,
      );
    } else if (mount.style == MountStyle.door) {
      final hinge = Offset(
        band.left + span.inwardX.abs() * band.width * 0.15 + (1 - span.inwardX.abs()) * 2,
        band.top + span.inwardZ.abs() * band.height * 0.15 + (1 - span.inwardZ.abs()) * 2,
      );
      canvas.drawCircle(hinge, 2.2, Paint()..color = color);
    } else if (mount.style == MountStyle.vent ||
        mount.style == MountStyle.intake ||
        mount.style == MountStyle.exhaust) {
      for (var i = 1; i <= 2; i++) {
        final t = i / 3;
        if (band.width >= band.height) {
          final y = band.top + band.height * t;
          canvas.drawLine(Offset(band.left + 2, y), Offset(band.right - 2, y), stroke);
        } else {
          final x = band.left + band.width * t;
          canvas.drawLine(Offset(x, band.top + 2), Offset(x, band.bottom - 2), stroke);
        }
      }
    }

    final label = shortFurnitureLabel(item);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: math.max(band.width, band.height));
    tp.paint(canvas, Offset(band.center.dx - tp.width / 2, band.center.dy - tp.height / 2));
  }

  static void _paintCeilingFixture2D(
    Canvas canvas,
    Rect roomRect,
    double cellW,
    double cellH,
    FurnitureItem item,
    bool selected,
  ) {
    final c = Offset(
      roomRect.left + (item.gridX + item.width / 2) * cellW,
      roomRect.top + (item.gridY + item.height / 2) * cellH,
    );
    final color = AppColors.lightingColor;
    canvas.drawCircle(c, selected ? 10 : 8, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawCircle(
      c,
      selected ? 10 : 8,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1.4,
    );
    canvas.drawCircle(c, 2.5, Paint()..color = color);
  }

  static void _addWallFitting3D(
    List<_PFace> faces,
    List<_BenchOverlay> overlays,
    FurnitureItem item,
    SurfaceMount mount,
    Size size,
    _Cam cam,
  ) {
    final span = mount.span!;
    final color = switch (mount.style) {
      MountStyle.window => AppColors.lightingColor,
      MountStyle.vent => AppColors.airflowColor,
      MountStyle.intake => AppColors.green,
      MountStyle.exhaust => AppColors.orange,
      MountStyle.door => AppColors.textSecondary,
      _ => categoryColor(item.category),
    };
    final inset = mount.protrusion;
    final leaf = [
      _V3(span.x0 + span.inwardX * inset, mount.bottomY, span.z0 + span.inwardZ * inset),
      _V3(span.x1 + span.inwardX * inset, mount.bottomY, span.z1 + span.inwardZ * inset),
      _V3(span.x1 + span.inwardX * inset, mount.topY, span.z1 + span.inwardZ * inset),
      _V3(span.x0 + span.inwardX * inset, mount.topY, span.z0 + span.inwardZ * inset),
    ];
    final face = _projectFace(_Face(leaf, color.withValues(alpha: 0.34)), size, cam);
    if (face == null) return;
    faces.add(face);

    if (mount.style == MountStyle.window) {
      final midY = (mount.bottomY + mount.topY) / 2;
      final vTop = _project(_alongWall(span, 0.5, mount.topY, inset), size, cam);
      final vBot = _project(_alongWall(span, 0.5, mount.bottomY, inset), size, cam);
      final hA = _project(_alongWall(span, 0.0, midY, inset), size, cam);
      final hB = _project(_alongWall(span, 1.0, midY, inset), size, cam);
      final sillA = _project(_alongWall(span, 0.0, mount.bottomY, inset + 0.12), size, cam);
      final sillB = _project(_alongWall(span, 1.0, mount.bottomY, inset + 0.12), size, cam);
      overlays.add(_BenchOverlay(face.depth - 0.01, (c) {
        final p = Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 1.2;
        if (vTop != null && vBot != null) c.drawLine(vTop.$1, vBot.$1, p);
        if (hA != null && hB != null) c.drawLine(hA.$1, hB.$1, p);
        if (sillA != null && sillB != null) {
          c.drawLine(
            sillA.$1,
            sillB.$1,
            Paint()
              ..color = color.withValues(alpha: 0.9)
              ..strokeWidth = 2.6,
          );
        }
      }));
    } else if (mount.style == MountStyle.door) {
      final radius = span.length;
      final alongX = (span.x1 - span.x0) / (radius == 0 ? 1 : radius);
      final alongZ = (span.z1 - span.z0) / (radius == 0 ? 1 : radius);
      final arc = <Offset>[];
      for (int i = 0; i <= 10; i++) {
        final t = i / 10;
        final angle = t * math.pi / 2;
        final px = span.x0 + (alongX * math.cos(angle) + span.inwardX * math.sin(angle)) * radius;
        final pz = span.z0 + (alongZ * math.cos(angle) + span.inwardZ * math.sin(angle)) * radius;
        final p = _project(_V3(px, 0.02, pz), size, cam);
        if (p == null) {
          arc.clear();
          break;
        }
        arc.add(p.$1);
      }
      final handle = _project(_alongWall(span, 0.82, mount.topY * 0.45, inset + 0.04), size, cam);
      overlays.add(_BenchOverlay(face.depth - 0.01, (c) {
        if (arc.length >= 2) {
          final path = Path()..moveTo(arc.first.dx, arc.first.dy);
          for (final pt in arc.skip(1)) {
            path.lineTo(pt.dx, pt.dy);
          }
          c.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        if (handle != null) {
          c.drawCircle(handle.$1, 2.4, Paint()..color = AppColors.amber);
        }
      }));
    } else if (mount.style == MountStyle.vent ||
        mount.style == MountStyle.intake ||
        mount.style == MountStyle.exhaust) {
      overlays.add(_BenchOverlay(face.depth - 0.01, (c) {
        for (var i = 1; i <= 3; i++) {
          final t = i / 4;
          final a = _project(_alongWall(span, 0.12, mount.bottomY + mount.height * t, inset + 0.02), size, cam);
          final b = _project(_alongWall(span, 0.88, mount.bottomY + mount.height * t, inset + 0.02), size, cam);
          if (a != null && b != null) {
            c.drawLine(
              a.$1,
              b.$1,
              Paint()
                ..color = color.withValues(alpha: 0.75)
                ..strokeWidth = 1.1,
            );
          }
        }
      }));
    }
  }

  static void _addCeilingFixture3D(
    List<_BenchOverlay> overlays,
    FurnitureItem item,
    SurfaceMount mount,
    Size size,
    _Cam cam,
  ) {
    final cx = item.gridX + item.width / 2;
    final cz = item.gridY + item.height / 2;
    final y = mount.bottomY;
    final center = _project(_V3(cx, y, cz), size, cam);
    if (center == null) return;
    overlays.add(_BenchOverlay(center.$2, (c) {
      c.drawCircle(center.$1, 10, Paint()..color = AppColors.lightingColor.withValues(alpha: 0.28));
      c.drawCircle(
        center.$1,
        10,
        Paint()
          ..color = AppColors.lightingColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      c.drawCircle(center.$1, 3, Paint()..color = AppColors.lightingColor);
    }));
  }

  static _V3 _alongWall(WallSpan span, double t, double y, double inset) {
    return _V3(
      span.x0 + (span.x1 - span.x0) * t + span.inwardX * inset,
      y,
      span.z0 + (span.z1 - span.z0) * t + span.inwardZ * inset,
    );
  }

  /// Wireframe room + detailed furniture meshes (shared by all Bench 3D views).
  static void paint3DScene(
    Canvas canvas,
    Size size, {
    required double roomWidth,
    required double roomDepth,
    required double roomHeight,
    required int gridCols,
    required int gridRows,
    required double yaw,
    required double pitch,
    required double distance,
    required double? lookAtX,
    required double? lookAtZ,
    required List<FurnitureItem> furniture,
  }) {
    final cam = _Cam(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
    );
    paintRoomWireframe(
      canvas,
      size,
      cam,
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    paint3D(
      canvas,
      size,
      cam,
      gridCols: gridCols,
      gridRows: gridRows,
      roomHeight: roomHeight,
      furniture: furniture,
    );
  }
}

/// Camera pose for Bench 3D painters — owned by [BenchOrbitShell] during orbit.
class BenchOrbitCamera {
  final double yaw;
  final double pitch;
  final double distance;
  final double lookAtX;
  final double lookAtZ;

  const BenchOrbitCamera({
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.lookAtX,
    required this.lookAtZ,
  });
}

/// Shared Bench 3D camera — matches Rig orbit (ScaleGestureRecognizer + internal state).
class BenchOrbitShell extends StatefulWidget {
  final Widget Function(BenchOrbitCamera camera) builder;
  final bool enabled;
  final double initialYaw;
  final double initialPitch;
  final double initialDistance;
  final double initialLookAtX;
  final double initialLookAtZ;
  final double roomWidth;
  final double roomDepth;
  final double minDistance;
  final double maxDistance;
  final int resetNonce;
  final VoidCallback? onDoubleTap;
  final ValueChanged<bool>? onDragChanged;
  final void Function(
    double yaw,
    double pitch,
    double distance,
    double lookAtX,
    double lookAtZ,
  )? onChanged;

  const BenchOrbitShell({
    super.key,
    required this.builder,
    this.enabled = true,
    this.initialYaw = 0,
    this.initialPitch = 0.34,
    this.initialDistance = 15,
    this.initialLookAtX = 3,
    this.initialLookAtZ = 4,
    this.roomWidth = 6,
    this.roomDepth = 8,
    this.onChanged,
    this.onDoubleTap,
    this.onDragChanged,
    this.resetNonce = 0,
    this.minDistance = 6,
    this.maxDistance = 32,
  });

  @override
  State<BenchOrbitShell> createState() => _BenchOrbitShellState();
}

class _BenchOrbitShellState extends State<BenchOrbitShell> {
  late double _yaw;
  late double _pitch;
  late double _distance;
  late double _lookAtX;
  late double _lookAtZ;
  double _scaleStartDistance = 15;
  bool _orbiting = false;
  int _lastResetNonce = 0;

  @override
  void initState() {
    super.initState();
    _applyInitials();
  }

  void _applyInitials() {
    _yaw = widget.initialYaw;
    _pitch = widget.initialPitch;
    _distance = widget.initialDistance;
    _lookAtX = widget.initialLookAtX;
    _lookAtZ = widget.initialLookAtZ;
    _scaleStartDistance = _distance;
    _lastResetNonce = widget.resetNonce;
  }

  @override
  void didUpdateWidget(BenchOrbitShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetNonce != _lastResetNonce) {
      _applyInitials();
    } else if (!_orbiting &&
        (oldWidget.initialYaw != widget.initialYaw ||
            oldWidget.initialPitch != widget.initialPitch ||
            oldWidget.initialDistance != widget.initialDistance)) {
      _applyInitials();
    }
  }

  BenchOrbitCamera get _camera => BenchOrbitCamera(
        yaw: _yaw,
        pitch: _pitch,
        distance: _distance,
        lookAtX: _lookAtX,
        lookAtZ: _lookAtZ,
      );

  void _notifyOptional() {
    widget.onChanged?.call(_yaw, _pitch, _distance, _lookAtX, _lookAtZ);
  }

  CameraPose _pose(double distance) => CameraPose(
        roomWidth: widget.roomWidth,
        roomDepth: widget.roomDepth,
        roomHeight: 2.8,
        yaw: _yaw,
        pitch: _pitch,
        distance: distance,
        lookAtX: _lookAtX,
        lookAtZ: _lookAtZ,
      );

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(_camera);
    if (!widget.enabled) return SizedBox.expand(child: content);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          setState(() {
            _distance = (_distance + signal.scrollDelta.dy * 0.02)
                .clamp(widget.minDistance, widget.maxDistance);
          });
          _notifyOptional();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          setState(_applyInitials);
          _notifyOptional();
          widget.onDoubleTap?.call();
        },
        onScaleStart: (_) {
          _orbiting = true;
          _scaleStartDistance = _distance;
          widget.onDragChanged?.call(true);
        },
        onScaleUpdate: (details) {
          setState(() {
            if (details.pointerCount >= 2) {
              final next = _scaleStartDistance / details.scale.clamp(0.15, 6.0);
              _distance = next.clamp(widget.minDistance, widget.maxDistance);
              final pose = _pose(_distance);
              final (right, fwd) = RoomProjection.floorPanAxes(pose);
              final pan = _distance * 0.00165;
              final dx = -details.focalPointDelta.dx * pan;
              final dz = details.focalPointDelta.dy * pan;
              _lookAtX = (pose.pivotX + right.x * dx + fwd.x * dz)
                  .clamp(-2.0, widget.roomWidth + 2.0);
              _lookAtZ = (pose.pivotZ + right.z * dx + fwd.z * dz)
                  .clamp(-2.0, widget.roomDepth + 2.0);
            } else {
              _yaw = (_yaw + details.focalPointDelta.dx * 0.008).clamp(-math.pi, math.pi);
              _pitch = (_pitch - details.focalPointDelta.dy * 0.006).clamp(-0.1, 1.0);
            }
          });
        },
        onScaleEnd: (_) {
          _orbiting = false;
          widget.onDragChanged?.call(false);
          _notifyOptional();
        },
        child: SizedBox.expand(child: content),
      ),
    );
  }
}
