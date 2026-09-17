// lib/widgets/rig_customizer/room_orbit_3d_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/room_model.dart';
import '../../models/surface_mount.dart';
import '../../theme/app_theme.dart';
import '../furniture_shapes.dart';
import '../room_orbit_projection.dart';
/// Corners of the room-facing surface of a wall fitting, inset from the wall by
/// [inset] grid units. Ordered bottom-start, bottom-end, top-end, top-start.
List<OrbitVec3> fittingFace(WallSpan span, double bottomY, double topY, double inset) {
  final ix = span.inwardX * inset;
  final iz = span.inwardZ * inset;
  return [
    OrbitVec3(span.x0 + ix, bottomY, span.z0 + iz),
    OrbitVec3(span.x1 + ix, bottomY, span.z1 + iz),
    OrbitVec3(span.x1 + ix, topY, span.z1 + iz),
    OrbitVec3(span.x0 + ix, topY, span.z0 + iz),
  ];
}

RoomRenderItem furnitureRenderItem({
  required FurnitureItem item,
  required int gridCols,
  required int gridRows,
  required List<FurnitureItem> furniture,
  required Color color,
  required bool selected,
  bool ghost = false,
}) {
  final kind = FurnitureShapes.kindOf(item);
  final mount = SurfaceMounts.of(
    item,
    gridCols: gridCols,
    gridRows: gridRows,
    furniture: furniture,
  );
  final yBase = (mount.isDesk || mount.isCeiling) ? mount.bottomY : 0.0;
  return RoomRenderItem(
    id: item.id,
    x: item.gridX,
    z: item.gridY,
    width: item.width,
    depth: item.height,
    yawDegrees: item.yawDegrees,
    color: color,
    selected: selected,
    ghost: ghost,
    isScanObject: false,
    label: item.name,
    heightY: yBase + FurnitureShapes.meshHeight(kind),
    kind: kind,
    mount: mount,
  );
}
/// A painted element paired with the depth it should sort at.
class _Drawable {
  final double depth;
  final void Function(Canvas canvas) paint;

  const _Drawable(this.depth, this.paint);
}

class RoomRenderItem {
  final String id;
  final double x;
  final double z;
  final double width;
  final double depth;
  final double heightY;
  final FurnitureKind kind;
  final double yawDegrees;
  final Color color;
  final bool selected;
  final bool isScanObject;
  final bool ghost;
  final String label;

  /// Whether this sits on the floor, a wall, or the ceiling.
  final SurfaceMount mount;

  const RoomRenderItem({
    required this.id,
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
    required this.heightY,
    this.kind = FurnitureKind.generic,
    this.yawDegrees = 0,
    this.mount = const SurfaceMount(
      surface: MountSurface.floor,
      style: MountStyle.floorItem,
      bottomY: 0,
      topY: 0.95,
    ),
    required this.color,
    required this.selected,
    required this.isScanObject,
    required this.label,
    this.ghost = false,
  });
}

class RoomOrbit3DPainter extends CustomPainter {
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
  final List<RoomRenderItem> items;

  RoomOrbit3DPainter({
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
    required this.items,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cam = CameraPose(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
    );

    _paintShell(canvas, size, cam);
    _paintFloorGrid(canvas, size, cam);

    final drawables = <_Drawable>[];
    for (final item in items) {
      final start = drawables.length;
      final mount = item.mount;
      if (mount.isWall && mount.span != null) {
        _collectWallFitting(drawables, item, mount, size, cam);
      } else if (mount.isCeiling) {
        _collectCeilingFixture(drawables, item, mount, size, cam);
      } else {
        _collectBox(drawables, item, size, cam);
      }
      if (item.ghost) {
        for (var i = start; i < drawables.length; i++) {
          final inner = drawables[i];
          drawables[i] = _Drawable(inner.depth, (canvas) {
            canvas.saveLayer(null, Paint()..color = const Color(0x62FFFFFF));
            inner.paint(canvas);
            canvas.restore();
          });
        }
      }
    }

    drawables.sort((a, b) => b.depth.compareTo(a.depth));
    for (final d in drawables) {
      d.paint(canvas);
    }
  }

  void _paintShell(Canvas canvas, Size size, CameraPose cam) {
    final floor = RoomProjection.projectFace(
      RoomFace(
        [
          OrbitVec3(0, 0, 0),
          OrbitVec3(roomWidth, 0, 0),
          OrbitVec3(roomWidth, 0, roomDepth),
          OrbitVec3(0, 0, roomDepth),
        ],
        AppColors.surfaceAlt.withValues(alpha: 0.72),
      ),
      size,
      cam,
    );
    if (floor != null) {
      canvas.drawPath(Path()..addPolygon(floor.points, true), Paint()..color = floor.color);
    }

    // Open wireframe shell — no solid wall faces, so the interior stays visible
    // when orbiting behind walls (matches Benchmark 3D).
    final corners = [
      OrbitVec3(0, 0, 0),
      OrbitVec3(roomWidth, 0, 0),
      OrbitVec3(roomWidth, 0, roomDepth),
      OrbitVec3(0, 0, roomDepth),
      OrbitVec3(0, roomHeight, 0),
      OrbitVec3(roomWidth, roomHeight, 0),
      OrbitVec3(roomWidth, roomHeight, roomDepth),
      OrbitVec3(0, roomHeight, roomDepth),
    ];
    final projected = corners.map((v) => RoomProjection.project(v, size, cam)).toList();
    final edge = Paint()
      ..color = AppColors.border.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    void line(int a, int b) {
      final pa = projected[a];
      final pb = projected[b];
      if (pa == null || pb == null) return;
      canvas.drawLine(pa.offset, pb.offset, edge);
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
  }

  void _paintFloorGrid(Canvas canvas, Size size, CameraPose cam) {
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (int c = 0; c <= gridCols; c++) {
      final a = RoomProjection.project(OrbitVec3(c.toDouble(), 0.001, 0), size, cam);
      final b = RoomProjection.project(OrbitVec3(c.toDouble(), 0.001, roomDepth), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }
    for (int r = 0; r <= gridRows; r++) {
      final a = RoomProjection.project(OrbitVec3(0, 0.001, r.toDouble()), size, cam);
      final b = RoomProjection.project(OrbitVec3(roomWidth, 0.001, r.toDouble()), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }
  }

  void _collectBox(List<_Drawable> out, RoomRenderItem item, Size size, CameraPose cam) {
    final List<RoomFace> faces;
    if (item.isScanObject) {
      final yTop = item.heightY;
      final a = OrbitVec3(item.x, 0, item.z);
      final b = OrbitVec3(item.x + item.width, 0, item.z);
      final c = OrbitVec3(item.x + item.width, 0, item.z + item.depth);
      final d = OrbitVec3(item.x, 0, item.z + item.depth);
      final a2 = OrbitVec3(item.x, yTop, item.z);
      final b2 = OrbitVec3(item.x + item.width, yTop, item.z);
      final c2 = OrbitVec3(item.x + item.width, yTop, item.z + item.depth);
      final d2 = OrbitVec3(item.x, yTop, item.z + item.depth);
      const sideBase = 0.28;
      faces = [
        RoomFace([a2, b2, c2, d2], item.color.withValues(alpha: item.selected ? 0.8 : 0.46)),
        RoomFace([a, b, b2, a2], item.color.withValues(alpha: sideBase)),
        RoomFace([b, c, c2, b2], item.color.withValues(alpha: sideBase + 0.06)),
        RoomFace([c, d, d2, c2], item.color.withValues(alpha: sideBase + 0.02)),
        RoomFace([d, a, a2, d2], item.color.withValues(alpha: sideBase - 0.02)),
      ];
    } else {
      final yBase = item.mount.isDesk ? item.mount.bottomY : 0.0;
      faces = FurnitureShapes.facesFor(
        FurnitureShapes.boxes(
          kind: item.kind,
          x: item.x,
          z: item.z,
          width: item.width,
          depth: item.depth,
          color: item.color,
          yBase: yBase,
          yawDegrees: item.yawDegrees,
        ),
      );
    }

    for (final face in faces) {
      final p = RoomProjection.projectFace(face, size, cam);
      if (p == null) continue;
      out.add(_Drawable(p.depth, (canvas) {
        final path = Path()..addPolygon(p.points, true);
        canvas.drawPath(path, Paint()..color = p.color);
        canvas.drawPath(
          path,
          Paint()
            ..color = (item.selected ? item.color : Colors.black).withValues(alpha: item.selected ? 0.85 : 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.selected ? 1.4 : 0.8,
        );
      }));
    }

    if (!FurnitureShapes.showsFacing(item.kind)) return;

    final yChev = item.mount.isDesk ? item.mount.bottomY + 0.02 : 0.02;
    final cx = item.x + item.width * 0.5;
    final cz = item.z + item.depth * 0.5;
    final rad = item.yawDegrees * math.pi / 180.0;
    final dirX = math.sin(rad);
    final dirZ = math.cos(rad);
    final reach = math.max(item.width, item.depth) * 0.55 + 0.2;
    final tip = OrbitVec3(cx + dirX * reach, yChev, cz + dirZ * reach);
    final back = OrbitVec3(cx + dirX * reach * 0.35, yChev, cz + dirZ * reach * 0.35);
    final px = -dirZ;
    final pz = dirX;
    final left = OrbitVec3(back.x + px * 0.18, yChev, back.z + pz * 0.18);
    final right = OrbitVec3(back.x - px * 0.18, yChev, back.z - pz * 0.18);
    final tipP = RoomProjection.project(tip, size, cam);
    final leftP = RoomProjection.project(left, size, cam);
    final rightP = RoomProjection.project(right, size, cam);
    if (tipP != null && leftP != null && rightP != null) {
      final depth = (tipP.depth + leftP.depth + rightP.depth) / 3;
      out.add(_Drawable(depth - 0.01, (canvas) {
        final path = Path()
          ..moveTo(tipP.offset.dx, tipP.offset.dy)
          ..lineTo(leftP.offset.dx, leftP.offset.dy)
          ..lineTo(rightP.offset.dx, rightP.offset.dy)
          ..close();
        canvas.drawPath(
          path,
          Paint()..color = (item.selected ? AppColors.cyan : item.color).withValues(alpha: 0.9),
        );
      }));
    }
  }

  void _collectWallFitting(
    List<_Drawable> out,
    RoomRenderItem item,
    SurfaceMount mount,
    Size size,
    CameraPose cam,
  ) {
    final span = mount.span!;
    switch (mount.style) {
      case MountStyle.window:
        _collectWindow(out, item, mount, span, size, cam);
      case MountStyle.door:
        _collectDoor(out, item, mount, span, size, cam);
      case MountStyle.vent:
        _collectVent(out, item, mount, span, size, cam);
      case MountStyle.intake:
      case MountStyle.exhaust:
        _collectVent(out, item, mount, span, size, cam);
      case MountStyle.floorItem:
      case MountStyle.deskItem:
      case MountStyle.ceilingFixture:
        _collectBox(out, item, size, cam);
    }
  }

  void _collectWindow(
    List<_Drawable> out,
    RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    final glass = fittingFace(span, mount.bottomY, mount.topY, 0.02);
    final face = RoomProjection.projectFace(
      RoomFace(glass, AppColors.lightingColor.withValues(alpha: item.selected ? 0.42 : 0.28)),
      size,
      cam,
    );
    if (face == null) return;

    // Mullion endpoints, projected up front so the closure just draws.
    final midY = (mount.bottomY + mount.topY) / 2;
    final midT = 0.5;
    final vTop = _projectAlongWall(span, midT, mount.topY, 0.02, size, cam);
    final vBottom = _projectAlongWall(span, midT, mount.bottomY, 0.02, size, cam);
    final hStart = _projectAlongWall(span, 0, midY, 0.02, size, cam);
    final hEnd = _projectAlongWall(span, 1, midY, 0.02, size, cam);
    final sillA = _projectAlongWall(span, 0, mount.bottomY, 0.14, size, cam);
    final sillB = _projectAlongWall(span, 1, mount.bottomY, 0.14, size, cam);

    out.add(_Drawable(face.depth, (canvas) {
      final path = Path()..addPolygon(face.points, true);
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.lightingColor.withValues(alpha: item.selected ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.selected ? 2.4 : 1.8,
      );

      final mullion = Paint()
        ..color = AppColors.lightingColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.2;
      if (vTop != null && vBottom != null) canvas.drawLine(vTop, vBottom, mullion);
      if (hStart != null && hEnd != null) canvas.drawLine(hStart, hEnd, mullion);

      // Sill: a small ledge that reads as the window sitting in the wall.
      if (sillA != null && sillB != null) {
        canvas.drawLine(
          sillA,
          sillB,
          Paint()
            ..color = AppColors.lightingColor.withValues(alpha: 0.85)
            ..strokeWidth = 3,
        );
      }
    }));
  }

  void _collectDoor(
    List<_Drawable> out,
    RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    final leaf = fittingFace(span, mount.bottomY, mount.topY, 0.02);
    final face = RoomProjection.projectFace(
      RoomFace(leaf, AppColors.textMuted.withValues(alpha: item.selected ? 0.42 : 0.26)),
      size,
      cam,
    );
    if (face == null) return;

    // Swing arc on the floor, hinged at the span start.
    final radius = span.length;
    final arc = <Offset>[];
    const steps = 12;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = t * math.pi / 2;
      // Sweep from along-wall toward the inward normal.
      final alongX = (span.x1 - span.x0) / (radius == 0 ? 1 : radius);
      final alongZ = (span.z1 - span.z0) / (radius == 0 ? 1 : radius);
      final px = span.x0 + (alongX * math.cos(angle) + span.inwardX * math.sin(angle)) * radius;
      final pz = span.z0 + (alongZ * math.cos(angle) + span.inwardZ * math.sin(angle)) * radius;
      final p = RoomProjection.project(OrbitVec3(px, 0.02, pz), size, cam);
      if (p == null) {
        arc.clear();
        break;
      }
      arc.add(p.offset);
    }

    final handle = _projectAlongWall(span, 0.82, mount.topY * 0.45, 0.05, size, cam);

    out.add(_Drawable(face.depth, (canvas) {
      final path = Path()..addPolygon(face.points, true);
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.textSecondary.withValues(alpha: item.selected ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.selected ? 2.4 : 1.8,
      );

      if (arc.length > 2) {
        final arcPath = Path()..moveTo(arc.first.dx, arc.first.dy);
        for (final p in arc.skip(1)) {
          arcPath.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          arcPath,
          Paint()
            ..color = AppColors.textSecondary.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.drawLine(
          arc.first,
          arc.last,
          Paint()
            ..color = AppColors.textSecondary.withValues(alpha: 0.28)
            ..strokeWidth = 1,
        );
      }

      if (handle != null) {
        canvas.drawCircle(handle, 2.4, Paint()..color = AppColors.textSecondary.withValues(alpha: 0.8));
      }
    }));
  }

  void _collectVent(
    List<_Drawable> out,
    RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    // An AC head visibly stands off the wall, so it gets a body with depth
    // rather than a flat decal.
    final inner = fittingFace(span, mount.bottomY, mount.topY, mount.protrusion);
    final outer = fittingFace(span, mount.bottomY, mount.topY, 0.01);

    final bodyFaces = <RoomFace>[
      RoomFace(inner, AppColors.airflowColor.withValues(alpha: item.selected ? 0.55 : 0.38)),
      // Underside, where the air actually leaves the unit.
      RoomFace(
        [outer[0], inner[0], inner[1], outer[1]],
        AppColors.airflowColor.withValues(alpha: 0.5),
      ),
      RoomFace(
        [outer[3], inner[3], inner[2], outer[2]],
        AppColors.airflowColor.withValues(alpha: 0.26),
      ),
    ];

    final louvers = <(Offset, Offset)>[];
    for (int i = 1; i <= 3; i++) {
      final y = mount.bottomY + (mount.topY - mount.bottomY) * (i / 5);
      final a = _projectAlongWall(span, 0.08, y, mount.protrusion + 0.01, size, cam);
      final b = _projectAlongWall(span, 0.92, y, mount.protrusion + 0.01, size, cam);
      if (a != null && b != null) louvers.add((a, b));
    }

    // Short arrows showing the throw direction into the room and downward.
    final throwLines = <(Offset, Offset)>[];
    for (final t in const [0.25, 0.5, 0.75]) {
      final from = _projectAlongWall(span, t, mount.bottomY, mount.protrusion, size, cam);
      final toX = span.x0 + (span.x1 - span.x0) * t + span.inwardX * 0.95;
      final toZ = span.z0 + (span.z1 - span.z0) * t + span.inwardZ * 0.95;
      final to = RoomProjection.project(OrbitVec3(toX, mount.bottomY - 0.55, toZ), size, cam);
      if (from != null && to != null) throwLines.add((from, to.offset));
    }

    for (final face in bodyFaces) {
      final p = RoomProjection.projectFace(face, size, cam);
      if (p == null) continue;
      final isInner = identical(face, bodyFaces.first);
      out.add(_Drawable(p.depth, (canvas) {
        final path = Path()..addPolygon(p.points, true);
        canvas.drawPath(path, Paint()..color = p.color);
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.airflowColor.withValues(alpha: item.selected ? 0.95 : 0.62)
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.selected ? 2.2 : 1.4,
        );
        if (!isInner) return;

        final louverPaint = Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.75)
          ..strokeWidth = 1.2;
        for (final (a, b) in louvers) {
          canvas.drawLine(a, b, louverPaint);
        }

        final throwPaint = Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.4;
        for (final (a, b) in throwLines) {
          canvas.drawLine(a, b, throwPaint);
        }
      }));
    }
  }

  void _collectCeilingFixture(
    List<_Drawable> out,
    RoomRenderItem item,
    SurfaceMount mount,
    Size size,
    CameraPose cam,
  ) {
    final cx = item.x + item.width / 2;
    final cz = item.z + item.depth / 2;
    final anchor = RoomProjection.project(OrbitVec3(cx, mount.topY, cz), size, cam);
    if (anchor == null) return;
    final lens = RoomProjection.project(OrbitVec3(cx, mount.bottomY, cz), size, cam);
    final floorSpot = RoomProjection.project(OrbitVec3(cx, 0.02, cz), size, cam);

    out.add(_Drawable(anchor.depth, (canvas) {
      if (lens != null) {
        canvas.drawLine(
          anchor.offset,
          lens.offset,
          Paint()
            ..color = AppColors.lightingColor.withValues(alpha: 0.6)
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(
          lens.offset,
          item.selected ? 11 : 9,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.30),
        );
        canvas.drawCircle(
          lens.offset,
          item.selected ? 5.5 : 4.5,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.95),
        );
      }
      // Faint pool on the floor so the fixture reads as lighting the room.
      if (floorSpot != null) {
        canvas.drawCircle(
          floorSpot.offset,
          22,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.07),
        );
      }
    }));
  }

  /// Projects a point [t] of the way along a wall span, [y] metres up, inset
  /// from the wall by [inset].
  Offset? _projectAlongWall(
    WallSpan span,
    double t,
    double y,
    double inset,
    Size size,
    CameraPose cam,
  ) {
    final x = span.x0 + (span.x1 - span.x0) * t + span.inwardX * inset;
    final z = span.z0 + (span.z1 - span.z0) * t + span.inwardZ * inset;
    return RoomProjection.project(OrbitVec3(x, y, z), size, cam)?.offset;
  }

  @override
  bool shouldRepaint(covariant RoomOrbit3DPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.distance != distance ||
        oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtZ != lookAtZ ||
        oldDelegate.items != items;
  }
}

class PickedEntity {
  final String id;
  final bool isScanObject;

  const PickedEntity({required this.id, required this.isScanObject});
}