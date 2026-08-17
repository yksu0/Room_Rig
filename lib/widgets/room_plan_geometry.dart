// lib/widgets/room_plan_geometry.dart
// Aspect-correct 2D room rect + grid mapping (matches 3D square-cell floor).
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../models/surface_mount.dart';

class RoomPlanGeometry {
  RoomPlanGeometry._();

  /// Letterboxed room rect — preserves gridCols:gridRows aspect (square cells).
  static Rect roomRectFor({
    required Size size,
    required int gridCols,
    required int gridRows,
    double pad = 12.0,
    double horizontalReserve = 0.0,
  }) {
    if (gridCols <= 0 || gridRows <= 0) {
      return Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    }
    final availW = (size.width - horizontalReserve - pad * 2).clamp(40.0, size.width);
    final availH = (size.height - pad * 2).clamp(40.0, size.height);
    final aspect = gridCols / gridRows;
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
      pad + horizontalReserve + (availW - roomW) / 2,
      pad + (availH - roomH) / 2,
      roomW,
      roomH,
    );
  }

  static double cellW(Rect roomRect, int gridCols) =>
      gridCols <= 0 ? roomRect.width : roomRect.width / gridCols;

  static double cellH(Rect roomRect, int gridRows) =>
      gridRows <= 0 ? roomRect.height : roomRect.height / gridRows;

  static Offset gridFromLocal(Offset local, Rect roomRect, int gridCols, int gridRows) {
    final cw = cellW(roomRect, gridCols);
    final ch = cellH(roomRect, gridRows);
    return Offset(
      (local.dx - roomRect.left) / cw,
      (local.dy - roomRect.top) / ch,
    );
  }

  static Rect itemRect(FurnitureItem item, Rect roomRect, int gridCols, int gridRows) {
    final cw = cellW(roomRect, gridCols);
    final ch = cellH(roomRect, gridRows);
    return Rect.fromLTWH(
      roomRect.left + item.gridX * cw,
      roomRect.top + item.gridY * ch,
      item.width * cw,
      item.height * ch,
    );
  }

  /// Smallest footprint under the tap wins.
  static FurnitureItem? hitTestFloor({
    required Offset local,
    required Rect roomRect,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    if (!roomRect.contains(local)) return null;
    final ordered = [...furniture]
      ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
    for (final item in ordered) {
      if (itemRect(item, roomRect, gridCols, gridRows).inflate(4).contains(local)) {
        return item;
      }
    }
    return null;
  }

  static bool hitWallBand({
    required Offset local,
    required Rect roomRect,
    required WallSpan span,
    required int gridCols,
    required int gridRows,
    double band = 46,
  }) {
    final cw = cellW(roomRect, gridCols);
    final ch = cellH(roomRect, gridRows);
    late Rect bandRect;
    switch (span.wall) {
      case RoomWall.north:
        bandRect = Rect.fromLTWH(
          roomRect.left + span.x0 * cw,
          roomRect.top,
          math.max((span.x1 - span.x0) * cw, 34),
          band,
        );
      case RoomWall.south:
        bandRect = Rect.fromLTWH(
          roomRect.left + span.x0 * cw,
          roomRect.bottom - band,
          math.max((span.x1 - span.x0) * cw, 34),
          band,
        );
      case RoomWall.west:
        bandRect = Rect.fromLTWH(
          roomRect.left,
          roomRect.top + span.z0 * ch,
          band,
          math.max((span.z1 - span.z0) * ch, 34),
        );
      case RoomWall.east:
        bandRect = Rect.fromLTWH(
          roomRect.right - band,
          roomRect.top + span.z0 * ch,
          band,
          math.max((span.z1 - span.z0) * ch, 34),
        );
    }
    return bandRect.inflate(2).contains(local);
  }

  static FurnitureItem? hitTest({
    required Offset local,
    required Rect roomRect,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
    required Map<String, SurfaceMount> mounts,
  }) {
    final floor = hitTestFloor(
      local: local,
      roomRect: roomRect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: [
        for (final f in furniture)
          if (!mounts[f.id]!.isWall) f,
      ],
    );
    if (floor != null) return floor;

    for (final item in furniture) {
      final mount = mounts[item.id]!;
      final span = mount.span;
      if (!mount.isWall || span == null) continue;
      if (hitWallBand(
        local: local,
        roomRect: roomRect,
        span: span,
        gridCols: gridCols,
        gridRows: gridRows,
      )) {
        return item;
      }
    }
    return null;
  }
}
