// lib/widgets/furniture_shapes.dart
// Plan (top-down) and orbit (3D) silhouettes. Door / window / wall AC stay on
// the wall-fitting painters. Everything else is a small cluster of boxes, built
// facing +Z (yaw 0) and then turned with the item so rotate moves the mesh.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import '../theme/app_theme.dart';
import 'room_orbit_projection.dart';

enum FurnitureKind {
  desk,
  table,
  chair,
  monitor,
  pc,
  bed,
  sofa,
  wardrobe,
  shelf,
  plant,
  tv,
  portableAc,
  fan,
  heater,
  taskLamp,
  floorLamp,
  ceilingLight,
  generic,
}

class FurnitureBox {
  final double x0;
  final double y0;
  final double z0;
  final double x1;
  final double y1;
  final double z1;
  final Color color;

  const FurnitureBox(this.x0, this.y0, this.z0, this.x1, this.y1, this.z1, this.color);
}

class FurnitureShapes {
  FurnitureShapes._();

  static const deskTopY = 0.74;

  static FurnitureKind kindOf(FurnitureItem item) => kindFrom(
        id: item.id,
        name: item.name,
        iconName: item.iconName,
      );

  static FurnitureKind kindFrom({
    required String id,
    required String name,
    required String iconName,
  }) {
    final hay = '$id $name $iconName'.toLowerCase();
    if (hay.contains('ceiling')) return FurnitureKind.ceilingLight;
    if (hay.contains('heater')) return FurnitureKind.heater;
    if ((hay.contains('floor') && hay.contains('lamp')) || iconName == 'floorLamp') {
      return FurnitureKind.floorLamp;
    }
    if (hay.contains('lamp') || hay.contains('light bar')) return FurnitureKind.taskLamp;
    if (iconName == 'monitor' || hay.contains('monitor')) return FurnitureKind.monitor;
    if (iconName == 'pc' || hay.contains('pc tower') || hay == 'pc') return FurnitureKind.pc;
    if (hay.contains('table')) return FurnitureKind.table;
    if (hay.contains('desk') && !hay.contains('fan')) return FurnitureKind.desk;
    if (hay.contains('chair')) return FurnitureKind.chair;
    if (hay.contains('bed')) return FurnitureKind.bed;
    if (hay.contains('sofa')) return FurnitureKind.sofa;
    if (hay.contains('wardrobe')) return FurnitureKind.wardrobe;
    if (hay.contains('shelf') || hay.contains('bookshelf')) return FurnitureKind.shelf;
    if (hay.contains('plant')) return FurnitureKind.plant;
    if (hay.contains('tv') || hay.contains('television')) return FurnitureKind.tv;
    if (hay.contains('portable') && hay.contains('ac')) return FurnitureKind.portableAc;
    if (hay.contains('fan')) return FurnitureKind.fan;
    return FurnitureKind.generic;
  }

  static bool showsFacing(FurnitureKind kind) {
    return kind == FurnitureKind.fan ||
        kind == FurnitureKind.heater ||
        kind == FurnitureKind.portableAc ||
        kind == FurnitureKind.chair ||
        kind == FurnitureKind.sofa ||
        kind == FurnitureKind.monitor ||
        kind == FurnitureKind.tv;
  }

  /// Floor and desk-top items. Door / window / wall AC / ceiling lights stay
  /// on their own wall and fixture painters so they are never floor cubes.
  static bool drawsMesh(FurnitureItem item) {
    if (item.hidden) return false;
    return !SurfaceMounts.isStructuralMount(item);
  }

  static double yBaseFor(FurnitureItem item, List<FurnitureItem> furniture) {
    if (SurfaceMounts.isDeskTopItem(item) &&
        SurfaceMounts.hostUnder(item, furniture) != null) {
      return deskTopY;
    }
    return 0;
  }

  static Rect planCell({
    required Rect room,
    required FurnitureItem item,
    required double roomWidth,
    required double roomDepth,
  }) {
    final rw = roomWidth <= 0 ? 1.0 : roomWidth;
    final rd = roomDepth <= 0 ? 1.0 : roomDepth;
    return Rect.fromLTRB(
      room.left + (item.gridX / rw) * room.width,
      room.top + (item.gridY / rd) * room.height,
      room.left + ((item.gridX + item.width) / rw) * room.width,
      room.top + ((item.gridY + item.height) / rd) * room.height,
    );
  }

  static void paintItemPlan(
    Canvas canvas,
    FurnitureItem item, {
    required Rect cell,
    required Color color,
    bool strong = false,
  }) {
    canvas.save();
    canvas.translate(cell.left, cell.top);
    paintPlan(
      canvas,
      cell.size,
      kindOf(item),
      color,
      selected: strong,
      yawDegrees: item.yawDegrees,
    );
    canvas.restore();
  }

  static List<FurnitureBox> boxesForItem(
    FurnitureItem item, {
    required List<FurnitureItem> furniture,
    required Color color,
  }) {
    return boxes(
      kind: kindOf(item),
      x: item.gridX,
      z: item.gridY,
      width: item.width,
      depth: item.height,
      color: color,
      yBase: yBaseFor(item, furniture),
      yawDegrees: item.yawDegrees,
    );
  }

  /// Metres of visual height for the 3D mesh (added on top of [yBase]).
  static double meshHeight(FurnitureKind kind) {
    switch (kind) {
      case FurnitureKind.desk:
        return 0.78;
      case FurnitureKind.table:
        return 0.5;
      case FurnitureKind.chair:
        return 0.98;
      case FurnitureKind.monitor:
        return 0.48;
      case FurnitureKind.pc:
        return 0.52;
      case FurnitureKind.bed:
        return 0.55;
      case FurnitureKind.sofa:
        return 0.78;
      case FurnitureKind.wardrobe:
        return 2.05;
      case FurnitureKind.shelf:
        return 1.72;
      case FurnitureKind.plant:
        return 0.62;
      case FurnitureKind.tv:
        return 0.82;
      case FurnitureKind.portableAc:
        return 0.78;
      case FurnitureKind.fan:
        return 1.22;
      case FurnitureKind.heater:
        return 0.46;
      case FurnitureKind.taskLamp:
        return 0.52;
      case FurnitureKind.floorLamp:
        return 1.52;
      case FurnitureKind.ceilingLight:
        return 0.14;
      case FurnitureKind.generic:
        return 0.9;
    }
  }

  static List<FurnitureBox> boxes({
    required FurnitureKind kind,
    required double x,
    required double z,
    required double width,
    required double depth,
    required Color color,
    double yBase = 0,
    double yawDegrees = 0,
  }) {
    final steps = (yawDegrees / 90).round();
    final swap = steps.abs() % 2 == 1;
    final canonW = swap ? depth : width;
    final canonD = swap ? width : depth;
    final cx = x + width * 0.5;
    final cz = z + depth * 0.5;
    final local = _orientedBoxes(
      kind: kind,
      x: cx - canonW * 0.5,
      z: cz - canonD * 0.5,
      width: canonW,
      depth: canonD,
      color: color,
      yBase: yBase,
    );
    if (steps % 4 == 0) return local;
    return [for (final b in local) _yawBox(b, cx, cz, yawDegrees)];
  }

  static FurnitureBox _yawBox(FurnitureBox b, double cx, double cz, double yawDegrees) {
    final rad = yawDegrees * math.pi / 180.0;
    final c = math.cos(rad);
    final s = math.sin(rad);
    double rx(double px, double pz) => cx + (px - cx) * c + (pz - cz) * s;
    double rz(double px, double pz) => cz - (px - cx) * s + (pz - cz) * c;
    final xs = [rx(b.x0, b.z0), rx(b.x1, b.z0), rx(b.x0, b.z1), rx(b.x1, b.z1)];
    final zs = [rz(b.x0, b.z0), rz(b.x1, b.z0), rz(b.x0, b.z1), rz(b.x1, b.z1)];
    return FurnitureBox(
      xs.reduce(math.min),
      b.y0,
      zs.reduce(math.min),
      xs.reduce(math.max),
      b.y1,
      zs.reduce(math.max),
      b.color,
    );
  }

  /// Built facing +Z (front = larger z). Rear / backrest sits at small z.
  static List<FurnitureBox> _orientedBoxes({
    required FurnitureKind kind,
    required double x,
    required double z,
    required double width,
    required double depth,
    required Color color,
    required double yBase,
  }) {
    Color c(double a) => color.withValues(alpha: a);
    final x1 = x + width;
    final z1 = z + depth;
    final y = yBase;

    List<FurnitureBox> box(double xa, double ya, double za, double xb, double yb, double zb, [double a = 0.55]) =>
        [FurnitureBox(xa, ya, za, xb, yb, zb, c(a))];

    switch (kind) {
      case FurnitureKind.desk:
        const top = 0.74;
        const thick = 0.05;
        const leg = 0.07;
        return [
          ...box(x, top - thick, z, x1, top, z1, 0.66),
          ...box(x + width * 0.08, top - 0.12, z + depth * 0.08, x1 - width * 0.08, top - thick, z + depth * 0.16, 0.4),
          ...box(x, 0, z, x + leg, top - thick, z + leg, 0.42),
          ...box(x1 - leg, 0, z, x1, top - thick, z + leg, 0.42),
          ...box(x, 0, z1 - leg, x + leg, top - thick, z1, 0.42),
          ...box(x1 - leg, 0, z1 - leg, x1, top - thick, z1, 0.42),
        ];
      case FurnitureKind.table:
        const top = 0.46;
        const thick = 0.05;
        const leg = 0.07;
        return [
          ...box(x, top - thick, z, x1, top, z1, 0.64),
          ...box(x, 0, z, x + leg, top - thick, z + leg, 0.4),
          ...box(x1 - leg, 0, z, x1, top - thick, z + leg, 0.4),
          ...box(x, 0, z1 - leg, x + leg, top - thick, z1, 0.4),
          ...box(x1 - leg, 0, z1 - leg, x1, top - thick, z1, 0.4),
        ];
      case FurnitureKind.chair:
        final seat = 0.42;
        return [
          ...box(x + width * 0.16, 0, z + depth * 0.18, x + width * 0.28, seat - 0.04, z + depth * 0.30, 0.38),
          ...box(x1 - width * 0.28, 0, z + depth * 0.18, x1 - width * 0.16, seat - 0.04, z + depth * 0.30, 0.38),
          ...box(x + width * 0.16, 0, z1 - depth * 0.30, x + width * 0.28, seat - 0.04, z1 - depth * 0.16, 0.38),
          ...box(x1 - width * 0.28, 0, z1 - depth * 0.30, x1 - width * 0.16, seat - 0.04, z1 - depth * 0.16, 0.38),
          ...box(x + width * 0.14, seat - 0.07, z + depth * 0.16, x1 - width * 0.14, seat, z1 - depth * 0.10, 0.58),
          ...box(x + width * 0.12, seat, z + depth * 0.06, x1 - width * 0.12, 0.96, z + depth * 0.28, 0.78),
          ...box(x + width * 0.08, seat, z + depth * 0.22, x + width * 0.16, seat + 0.16, z1 - depth * 0.18, 0.5),
          ...box(x1 - width * 0.16, seat, z + depth * 0.22, x1 - width * 0.08, seat + 0.16, z1 - depth * 0.18, 0.5),
        ];
      case FurnitureKind.monitor:
        return [
          ...box(x + width * 0.28, y, z + depth * 0.30, x1 - width * 0.28, y + 0.05, z1 - depth * 0.18, 0.42),
          ...box(x + width * 0.46, y + 0.05, z + depth * 0.48, x1 - width * 0.46, y + 0.16, z1 - depth * 0.28, 0.5),
          ...box(x + width * 0.06, y + 0.16, z + depth * 0.62, x1 - width * 0.06, y + 0.48, z1 - depth * 0.08, 0.82),
        ];
      case FurnitureKind.pc:
        return [
          ...box(x + width * 0.22, y, z + depth * 0.12, x1 - width * 0.22, y + 0.50, z1 - depth * 0.12, 0.7),
          ...box(x + width * 0.26, y + 0.08, z1 - depth * 0.16, x1 - width * 0.26, y + 0.44, z1 - depth * 0.10, 0.45),
          ...box(x + width * 0.30, y + 0.42, z + depth * 0.16, x1 - width * 0.30, y + 0.48, z + depth * 0.40, 0.85),
        ];
      case FurnitureKind.bed:
        return [
          ...box(x, 0.04, z, x1, 0.18, z1, 0.4),
          ...box(x + width * 0.04, 0.18, z + depth * 0.04, x1 - width * 0.04, 0.38, z1 - depth * 0.04, 0.58),
          ...box(x + width * 0.06, 0.38, z + depth * 0.06, x1 - width * 0.06, 0.46, z1 - depth * 0.28, 0.7),
          ...box(x + width * 0.08, 0.46, z + depth * 0.04, x + width * 0.46, 0.55, z + depth * 0.22, 0.8),
          ...box(x1 - width * 0.46, 0.46, z + depth * 0.04, x1 - width * 0.08, 0.55, z + depth * 0.22, 0.8),
        ];
      case FurnitureKind.sofa:
        return [
          ...box(x + width * 0.08, 0.08, z + depth * 0.22, x1 - width * 0.08, 0.40, z1 - depth * 0.06, 0.55),
          ...box(x, 0.40, z, x1, 0.76, z + depth * 0.30, 0.74),
          ...box(x, 0.18, z + depth * 0.16, x + width * 0.10, 0.62, z1, 0.62),
          ...box(x1 - width * 0.10, 0.18, z + depth * 0.16, x1, 0.62, z1, 0.62),
        ];
      case FurnitureKind.wardrobe:
        return [
          ...box(x, 0, z, x1, 2.02, z1, 0.55),
          ...box(x + width * 0.48, 0.12, z + depth * 0.02, x + width * 0.52, 1.92, z1 - depth * 0.02, 0.88),
          ...box(x + width * 0.18, 0.95, z + depth * 0.02, x + width * 0.26, 1.02, z1 - depth * 0.02, 0.9),
          ...box(x1 - width * 0.26, 0.95, z + depth * 0.02, x1 - width * 0.18, 1.02, z1 - depth * 0.02, 0.9),
          ...box(x, 0, z, x1, 0.10, z1, 0.7),
        ];
      case FurnitureKind.shelf:
        return [
          ...box(x, 0, z, x + width * 0.10, 1.70, z1, 0.42),
          ...box(x1 - width * 0.10, 0, z, x1, 1.70, z1, 0.42),
          ...box(x + width * 0.08, 0, z, x1 - width * 0.08, 1.70, z + depth * 0.10, 0.35),
          ...box(x, 0.08, z + depth * 0.08, x1, 0.16, z1, 0.62),
          ...box(x, 0.58, z + depth * 0.08, x1, 0.66, z1, 0.62),
          ...box(x, 1.08, z + depth * 0.08, x1, 1.16, z1, 0.62),
          ...box(x, 1.58, z + depth * 0.08, x1, 1.70, z1, 0.58),
        ];
      case FurnitureKind.plant:
        return [
          ...box(x + width * 0.30, 0, z + depth * 0.30, x1 - width * 0.30, 0.16, z1 - depth * 0.30, 0.55),
          ...box(x + width * 0.34, 0.16, z + depth * 0.34, x1 - width * 0.34, 0.20, z1 - depth * 0.34, 0.4),
          ...box(x + width * 0.22, 0.20, z + depth * 0.18, x1 - width * 0.22, 0.42, z1 - depth * 0.22, 0.48),
          ...box(x + width * 0.12, 0.32, z + depth * 0.28, x + width * 0.42, 0.58, z1 - depth * 0.22, 0.42),
          ...box(x1 - width * 0.42, 0.28, z + depth * 0.16, x1 - width * 0.10, 0.62, z1 - depth * 0.28, 0.4),
        ];
      case FurnitureKind.tv:
        return [
          ...box(x + width * 0.32, 0, z + depth * 0.28, x1 - width * 0.32, 0.08, z1 - depth * 0.18, 0.45),
          ...box(x + width * 0.46, 0.08, z + depth * 0.42, x1 - width * 0.46, 0.22, z1 - depth * 0.28, 0.5),
          ...box(x, 0.22, z + depth * 0.58, x1, 0.80, z1 - depth * 0.06, 0.84),
        ];
      case FurnitureKind.portableAc:
        return [
          ...box(x + width * 0.14, 0, z + depth * 0.16, x1 - width * 0.14, 0.70, z1 - depth * 0.10, 0.6),
          ...box(x + width * 0.22, 0.52, z + depth * 0.08, x1 - width * 0.22, 0.64, z + depth * 0.18, 0.45),
          ...box(x + width * 0.22, 0.18, z1 - depth * 0.16, x1 - width * 0.22, 0.58, z1 - depth * 0.06, 0.4),
          ...box(x + width * 0.42, 0.70, z + depth * 0.22, x1 - width * 0.42, 0.78, z + depth * 0.40, 0.75),
        ];
      case FurnitureKind.fan:
        return [
          ...box(x + width * 0.28, 0, z + depth * 0.28, x1 - width * 0.28, 0.08, z1 - depth * 0.28, 0.45),
          ...box(x + width * 0.44, 0.08, z + depth * 0.44, x1 - width * 0.44, 0.88, z1 - depth * 0.44, 0.4),
          ...box(x + width * 0.36, 0.82, z + depth * 0.36, x1 - width * 0.36, 0.98, z1 - depth * 0.36, 0.7),
          ...box(x + width * 0.08, 0.88, z + depth * 0.38, x1 - width * 0.08, 1.20, z1 - depth * 0.22, 0.55),
        ];
      case FurnitureKind.heater:
        return [
          ...box(x + width * 0.08, 0, z + depth * 0.22, x1 - width * 0.08, 0.40, z1 - depth * 0.16, 0.58),
          ...box(x + width * 0.16, 0.08, z1 - depth * 0.20, x + width * 0.22, 0.34, z1 - depth * 0.10, 0.8),
          ...box(x + width * 0.38, 0.08, z1 - depth * 0.20, x + width * 0.44, 0.34, z1 - depth * 0.10, 0.8),
          ...box(x + width * 0.60, 0.08, z1 - depth * 0.20, x + width * 0.66, 0.34, z1 - depth * 0.10, 0.8),
          ...box(x + width * 0.78, 0.08, z1 - depth * 0.20, x + width * 0.84, 0.34, z1 - depth * 0.10, 0.8),
        ];
      case FurnitureKind.taskLamp:
        return [
          ...box(x + width * 0.34, y, z + depth * 0.34, x1 - width * 0.34, y + 0.06, z1 - depth * 0.34, 0.5),
          ...box(x + width * 0.46, y + 0.06, z + depth * 0.46, x1 - width * 0.46, y + 0.30, z1 - depth * 0.46, 0.4),
          ...box(x + width * 0.30, y + 0.28, z + depth * 0.22, x1 - width * 0.22, y + 0.36, z + depth * 0.48, 0.55),
          ...box(x + width * 0.16, y + 0.34, z + depth * 0.12, x1 - width * 0.38, y + 0.50, z + depth * 0.40, 0.75),
        ];
      case FurnitureKind.floorLamp:
        return [
          ...box(x + width * 0.28, 0, z + depth * 0.28, x1 - width * 0.28, 0.08, z1 - depth * 0.28, 0.5),
          ...box(x + width * 0.44, 0.08, z + depth * 0.44, x1 - width * 0.44, 1.18, z1 - depth * 0.44, 0.4),
          ...box(x + width * 0.16, 1.14, z + depth * 0.16, x1 - width * 0.16, 1.50, z1 - depth * 0.16, 0.68),
        ];
      case FurnitureKind.ceilingLight:
        return [
          ...box(x + width * 0.42, y + 0.08, z + depth * 0.42, x1 - width * 0.42, y + 0.14, z1 - depth * 0.42, 0.5),
          ...box(x + width * 0.16, y, z + depth * 0.16, x1 - width * 0.16, y + 0.08, z1 - depth * 0.16, 0.75),
        ];
      case FurnitureKind.generic:
        return box(x + width * 0.08, y, z + depth * 0.08, x1 - width * 0.08, y + 0.9, z1 - depth * 0.08, 0.5);
    }
  }

  static List<RoomFace> facesFor(List<FurnitureBox> parts) {
    final faces = <RoomFace>[];
    for (final b in parts) {
      final a = OrbitVec3(b.x0, b.y0, b.z0);
      final c = OrbitVec3(b.x1, b.y0, b.z0);
      final d = OrbitVec3(b.x1, b.y0, b.z1);
      final e = OrbitVec3(b.x0, b.y0, b.z1);
      final a2 = OrbitVec3(b.x0, b.y1, b.z0);
      final c2 = OrbitVec3(b.x1, b.y1, b.z0);
      final d2 = OrbitVec3(b.x1, b.y1, b.z1);
      final e2 = OrbitVec3(b.x0, b.y1, b.z1);
      faces.addAll([
        RoomFace([a2, c2, d2, e2], b.color),
        RoomFace([a, c, c2, a2], b.color.withValues(alpha: (b.color.a * 0.85).clamp(0.15, 1))),
        RoomFace([c, d, d2, c2], b.color),
        RoomFace([d, e, e2, d2], b.color.withValues(alpha: (b.color.a * 0.9).clamp(0.15, 1))),
        RoomFace([e, a, a2, e2], b.color),
      ]);
    }
    return faces;
  }

  static void paintPlan(
    Canvas canvas,
    Size size,
    FurnitureKind kind,
    Color color, {
    bool selected = false,
    bool hasConflict = false,
    double yawDegrees = 0,
  }) {
    final steps = (yawDegrees / 90).round();
    final swap = steps.abs() % 2 == 1;
    final canon = swap ? Size(size.height, size.width) : size;

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.rotate(yawDegrees * math.pi / 180.0);
    canvas.translate(-canon.width * 0.5, -canon.height * 0.5);
    _paintPlanLocal(
      canvas,
      canon,
      kind,
      color,
      selected: selected,
      hasConflict: hasConflict,
    );
    canvas.restore();
  }

  static void _paintPlanLocal(
    Canvas canvas,
    Size size,
    FurnitureKind kind,
    Color color, {
    required bool selected,
    required bool hasConflict,
  }) {
    final stroke = Paint()
      ..color = (hasConflict ? AppColors.red : color).withValues(alpha: selected ? 0.95 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.0 : 1.3
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: selected ? 0.22 : 0.12);
    final heavy = Paint()..color = color.withValues(alpha: selected ? 0.38 : 0.22);

    Rect inset(double l, double t, double r, double b) => Rect.fromLTRB(
          size.width * l,
          size.height * t,
          size.width * r,
          size.height * b,
        );

    void rrect(Rect r, [Paint? p]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), p ?? fill);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), stroke);
    }

    switch (kind) {
      case FurnitureKind.desk:
      case FurnitureKind.table:
        rrect(inset(0.04, 0.14, 0.96, 0.86), heavy);
        rrect(inset(0.04, 0.14, 0.16, 0.28));
        rrect(inset(0.84, 0.14, 0.96, 0.28));
        rrect(inset(0.04, 0.72, 0.16, 0.86));
        rrect(inset(0.84, 0.72, 0.96, 0.86));
        if (kind == FurnitureKind.desk) {
          canvas.drawLine(
            Offset(size.width * 0.12, size.height * 0.22),
            Offset(size.width * 0.88, size.height * 0.22),
            stroke,
          );
        }
      case FurnitureKind.chair:
        rrect(inset(0.16, 0.08, 0.84, 0.34), heavy);
        rrect(inset(0.18, 0.32, 0.82, 0.90));
        rrect(inset(0.08, 0.36, 0.20, 0.82));
        rrect(inset(0.80, 0.36, 0.92, 0.82));
      case FurnitureKind.monitor:
        rrect(inset(0.30, 0.62, 0.70, 0.92));
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.62),
          Offset(size.width * 0.5, size.height * 0.48),
          stroke,
        );
        rrect(inset(0.06, 0.18, 0.94, 0.50), heavy);
      case FurnitureKind.pc:
        rrect(inset(0.26, 0.10, 0.74, 0.90), heavy);
        for (final t in const [0.28, 0.42, 0.56, 0.70]) {
          canvas.drawLine(
            Offset(size.width * 0.34, size.height * t),
            Offset(size.width * 0.66, size.height * t),
            stroke,
          );
        }
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.82), 3, stroke);
      case FurnitureKind.bed:
        rrect(inset(0.06, 0.08, 0.94, 0.92));
        rrect(inset(0.10, 0.08, 0.90, 0.28), heavy);
        rrect(inset(0.14, 0.12, 0.46, 0.26));
        rrect(inset(0.54, 0.12, 0.86, 0.26));
      case FurnitureKind.sofa:
        rrect(inset(0.06, 0.08, 0.94, 0.36), heavy);
        rrect(inset(0.14, 0.32, 0.86, 0.90));
        rrect(inset(0.04, 0.28, 0.18, 0.90));
        rrect(inset(0.82, 0.28, 0.96, 0.90));
      case FurnitureKind.wardrobe:
        rrect(inset(0.10, 0.06, 0.90, 0.94), heavy);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.10),
          Offset(size.width * 0.5, size.height * 0.90),
          stroke,
        );
        canvas.drawCircle(Offset(size.width * 0.38, size.height * 0.52), 2.4, stroke);
        canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.52), 2.4, stroke);
      case FurnitureKind.shelf:
        rrect(inset(0.12, 0.06, 0.88, 0.94));
        for (final t in const [0.26, 0.46, 0.66, 0.84]) {
          canvas.drawLine(
            Offset(size.width * 0.16, size.height * t),
            Offset(size.width * 0.84, size.height * t),
            stroke,
          );
        }
      case FurnitureKind.plant:
        canvas.drawOval(inset(0.30, 0.62, 0.70, 0.94), heavy);
        canvas.drawOval(inset(0.30, 0.62, 0.70, 0.94), stroke);
        canvas.drawOval(inset(0.16, 0.10, 0.54, 0.58), fill);
        canvas.drawOval(inset(0.16, 0.10, 0.54, 0.58), stroke);
        canvas.drawOval(inset(0.46, 0.16, 0.86, 0.64), fill);
        canvas.drawOval(inset(0.46, 0.16, 0.86, 0.64), stroke);
      case FurnitureKind.tv:
        rrect(inset(0.28, 0.70, 0.72, 0.92));
        rrect(inset(0.04, 0.18, 0.96, 0.68), heavy);
      case FurnitureKind.portableAc:
        rrect(inset(0.18, 0.12, 0.82, 0.88), heavy);
        for (final t in const [0.32, 0.48, 0.64]) {
          canvas.drawLine(
            Offset(size.width * 0.28, size.height * t),
            Offset(size.width * 0.72, size.height * t),
            stroke,
          );
        }
        rrect(inset(0.40, 0.06, 0.60, 0.16));
      case FurnitureKind.fan:
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.58), size.shortestSide * 0.16, fill);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.42), size.shortestSide * 0.34, fill);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.42), size.shortestSide * 0.34, stroke);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.42), 3, stroke);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.42),
          Offset(size.width * 0.5, size.height * 0.12),
          stroke,
        );
      case FurnitureKind.heater:
        rrect(inset(0.10, 0.28, 0.90, 0.78), heavy);
        for (final t in const [0.28, 0.44, 0.60, 0.76]) {
          canvas.drawLine(
            Offset(size.width * t, size.height * 0.34),
            Offset(size.width * t, size.height * 0.72),
            stroke,
          );
        }
      case FurnitureKind.taskLamp:
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.78), 5, heavy);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.78), 5, stroke);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.74),
          Offset(size.width * 0.38, size.height * 0.38),
          stroke,
        );
        canvas.drawOval(inset(0.18, 0.12, 0.58, 0.42), fill);
        canvas.drawOval(inset(0.18, 0.12, 0.58, 0.42), stroke);
      case FurnitureKind.floorLamp:
        canvas.drawOval(inset(0.32, 0.82, 0.68, 0.96), fill);
        canvas.drawOval(inset(0.32, 0.82, 0.68, 0.96), stroke);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.84),
          Offset(size.width * 0.5, size.height * 0.28),
          stroke,
        );
        canvas.drawOval(inset(0.22, 0.06, 0.78, 0.32), fill);
        canvas.drawOval(inset(0.22, 0.06, 0.78, 0.32), stroke);
      case FurnitureKind.ceilingLight:
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), size.shortestSide * 0.32, fill);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), size.shortestSide * 0.32, stroke);
        canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), size.shortestSide * 0.12, stroke);
      case FurnitureKind.generic:
        rrect(inset(0.1, 0.1, 0.9, 0.9));
    }
  }
}
