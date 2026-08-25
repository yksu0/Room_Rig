// lib/services/layout_orientation.dart
// Shared facing rules for Auto-Rig / Bench optimizers.
//
// Research-backed defaults encoded here:
// - Seating faces focal points (desk, TV) or into the room, never into a wall
//   (interior circulation / sofa placement guidance).
// - Desk work: chair faces the desk; monitor faces the user (ISO/BIFMA-style
//   reach zones assume the user faces the task surface).
// - Fans / portable units aim into open floor volume, not plaster (HVAC throw
//   should mix with room air, not stall on a boundary).
//
// Yaw convention matches [FurnitureShapes]: 0° = +Z (increasing gridY).
import 'dart:math';

import '../models/room_model.dart';
import '../models/surface_mount.dart';
import '../widgets/furniture_shapes.dart';

class LayoutOrientation {
  LayoutOrientation._();

  static double normalizeYaw(double degrees) {
    var d = degrees % 360;
    if (d < 0) d += 360;
    return ((d / 90).round() * 90) % 360;
  }

  /// Bearing from (fromX, fromZ) to (toX, toZ) on the floor plan.
  static double yawToward({
    required double fromX,
    required double fromZ,
    required double toX,
    required double toZ,
  }) {
    final dx = toX - fromX;
    final dz = toZ - fromZ;
    if (dx.abs() < 1e-6 && dz.abs() < 1e-6) return 0;
    return normalizeYaw(atan2(dx, dz) * 180 / pi);
  }

  /// Face away from the nearest perimeter wall into the room.
  static double inwardFromNearestWall({
    required double gridX,
    required double gridY,
    required double width,
    required double height,
    required int gridCols,
    required int gridRows,
  }) {
    final cx = gridX + width * 0.5;
    final cz = gridY + height * 0.5;
    final dNorth = cz;
    final dSouth = gridRows - cz;
    final dWest = cx;
    final dEast = gridCols - cx;
    final minDist = [dNorth, dSouth, dWest, dEast].reduce(min);
    if (minDist == dNorth) return 0;
    if (minDist == dSouth) return 180;
    if (minDist == dWest) return 90;
    return 270;
  }

  static ({double x, double z}) _center(FurnitureItem item) => (
        x: item.gridX + item.width * 0.5,
        z: item.gridY + item.height * 0.5,
      );

  static FurnitureItem? _first(List<FurnitureItem> items, bool Function(FurnitureItem) test) {
    for (final f in items) {
      if (test(f)) return f;
    }
    return null;
  }

  /// Apply post-placement yaw for every item that has a meaningful front.
  static List<FurnitureItem> apply({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final desks = furniture.where(SurfaceMounts.isDeskHost).toList()
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final desk = desks.isEmpty ? null : desks.first;
    final chair = _first(furniture, (f) {
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      return f.iconName == 'chair' || hay.contains('chair') || hay.contains('seat');
    });
    final sofa = _first(
      furniture,
      (f) => f.iconName == 'sofa' || '${f.id} ${f.name}'.toLowerCase().contains('sofa'),
    );
    final tv = _first(
      furniture,
      (f) => f.iconName == 'tv' || '${f.id} ${f.name}'.toLowerCase().contains('tv'),
    );
    final roomCx = gridCols * 0.5;
    final roomCz = gridRows * 0.5;

    return furniture.map((item) {
      if (item.locked) return item.copyWith();
      final kind = FurnitureShapes.kindOf(item);
      final c = _center(item);

      switch (kind) {
        case FurnitureKind.chair:
          if (desk != null) {
            final d = _center(desk);
            return item.copyWith(
              yawDegrees: yawToward(
                fromX: c.x,
                fromZ: c.z,
                toX: d.x,
                toZ: d.z,
              ),
            );
          }
          return _faceIntoRoom(item, gridCols, gridRows);

        case FurnitureKind.sofa:
        case FurnitureKind.bed:
          if (kind == FurnitureKind.sofa && tv != null) {
            final t = _center(tv);
            return item.copyWith(
              yawDegrees: yawToward(
                fromX: c.x,
                fromZ: c.z,
                toX: t.x,
                toZ: t.z,
              ),
            );
          }
          return _faceIntoRoom(item, gridCols, gridRows);

        case FurnitureKind.monitor:
          // Screen faces the seated user (ISO visual display terminal posture).
          if (chair != null) {
            final u = _center(chair);
            return item.copyWith(
              yawDegrees: yawToward(
                fromX: c.x,
                fromZ: c.z,
                toX: u.x,
                toZ: u.z,
              ),
            );
          }
          if (desk != null) {
            final d = _center(desk);
            return item.copyWith(
              yawDegrees: yawToward(
                fromX: c.x,
                fromZ: c.z,
                toX: d.x,
                toZ: d.z + desk.height,
              ),
            );
          }
          return item;

        case FurnitureKind.tv:
          if (sofa != null) {
            final s = _center(sofa);
            return item.copyWith(
              yawDegrees: yawToward(
                fromX: c.x,
                fromZ: c.z,
                toX: s.x,
                toZ: s.z,
              ),
            );
          }
          return _faceIntoRoom(item, gridCols, gridRows);

        case FurnitureKind.fan:
        case FurnitureKind.heater:
        case FurnitureKind.portableAc:
          return item.copyWith(
            yawDegrees: yawToward(
              fromX: c.x,
              fromZ: c.z,
              toX: roomCx,
              toZ: roomCz,
            ),
          );

        default:
          return item;
      }
    }).toList(growable: false);
  }

  static FurnitureItem _faceIntoRoom(
    FurnitureItem item,
    int gridCols,
    int gridRows,
  ) {
    return item.copyWith(
      yawDegrees: inwardFromNearestWall(
        gridX: item.gridX,
        gridY: item.gridY,
        width: item.width,
        height: item.height,
        gridCols: gridCols,
        gridRows: gridRows,
      ),
    );
  }

  /// True when the item's front (+Z from yaw) points into the nearest wall
  /// within ~0.6 cells — the classic "sofa facing plaster" failure mode.
  static bool facesIntoWall({
    required FurnitureItem item,
    required int gridCols,
    required int gridRows,
  }) {
    if (!FurnitureShapes.showsFacing(FurnitureShapes.kindOf(item))) return false;
    final rad = item.yawDegrees * pi / 180.0;
    final fx = sin(rad);
    final fz = cos(rad);
    final cx = item.gridX + item.width * 0.5;
    final cz = item.gridY + item.height * 0.5;
    const probe = 0.75;
    final tx = cx + fx * probe;
    final tz = cz + fz * probe;
    if (tx < 0.35 || tz < 0.35 || tx > gridCols - 0.35 || tz > gridRows - 0.35) {
      return true;
    }
    return false;
  }
}
