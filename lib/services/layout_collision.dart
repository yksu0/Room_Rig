// lib/services/layout_collision.dart
import '../models/room_model.dart';
import '../models/surface_mount.dart';

enum LayoutConflictKind { overlap, blockedOpening, tightClearance }

class LayoutConflict {
  final LayoutConflictKind kind;
  final String message;
  final List<String> itemIds;

  const LayoutConflict({
    required this.kind,
    required this.message,
    required this.itemIds,
  });
}

class LayoutMoveResult {
  final double gridX;
  final double gridY;
  final bool blocked;
  final bool snapped;

  const LayoutMoveResult({
    required this.gridX,
    required this.gridY,
    this.blocked = false,
    this.snapped = false,
  });
}

/// 2D layout collision helpers for drag + conflict warnings.
class LayoutCollision {
  LayoutCollision._();

  static const snapStep = 0.25;
  static const nonColliding = {'window', 'door'};

  static bool overlaps(FurnitureItem a, FurnitureItem b) {
    return a.gridX < b.gridX + b.width &&
        a.gridX + a.width > b.gridX &&
        a.gridY < b.gridY + b.height &&
        a.gridY + a.height > b.gridY;
  }

  static bool _isOpening(FurnitureItem f) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();
    return id.contains('window') ||
        id.contains('door') ||
        name.contains('window') ||
        name.contains('door');
  }

  /// Wall-mounted fittings do not contest floor space: an AC head at 1.4–2.3 m
  /// has to be free to sit above a desk, the same way the airflow model treats
  /// it as a thin wall device rather than a solid block.
  static bool _skipsCollision(FurnitureItem f) => skipsFloorOccupancy(f);

  /// Openings, vents and ceiling fixtures do not take floor cells. A monitor
  /// on a desk is handled separately so it still clashes with another lamp
  /// on the same top.
  static bool skipsFloorOccupancy(FurnitureItem f) =>
      nonColliding.contains(f.id) ||
      _isOpening(f) ||
      SurfaceMounts.isVent(f) ||
      SurfaceMounts.isIntake(f) ||
      SurfaceMounts.isExhaust(f) ||
      SurfaceMounts.isCeilingFixture(f);

  static bool itemCollides(FurnitureItem candidate, List<FurnitureItem> furniture) =>
      _collidesWithOthers(candidate, furniture);

  static double snap(double v) => (v / snapStep).round() * snapStep;

  /// Resolve a proposed drag position: snap, clamp to room, reject overlaps.
  static LayoutMoveResult resolveMove({
    required String id,
    required double proposedX,
    required double proposedY,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    bool allowOverlap = false,
  }) {
    FurnitureItem? moving;
    for (final f in furniture) {
      if (f.id == id) {
        moving = f;
        break;
      }
    }
    if (moving == null) {
      return LayoutMoveResult(gridX: proposedX, gridY: proposedY, blocked: true);
    }

    final maxX = (gridCols - moving.width).clamp(0.0, gridCols.toDouble());
    final maxY = (gridRows - moving.height).clamp(0.0, gridRows.toDouble());
    var x = snap(proposedX).clamp(0.0, maxX);
    var y = snap(proposedY).clamp(0.0, maxY);

    if (allowOverlap || _skipsCollision(moving)) {
      return LayoutMoveResult(gridX: x, gridY: y, snapped: true);
    }

    final candidate = moving.copyWith(gridX: x, gridY: y);
    if (!_collidesWithOthers(candidate, furniture)) {
      return LayoutMoveResult(gridX: x, gridY: y, snapped: true);
    }

    // Try axis slides from last valid intent (prefer X then Y then both).
    final xOnly = moving.copyWith(gridX: x);
    if (!_collidesWithOthers(xOnly, furniture)) {
      return LayoutMoveResult(gridX: x, gridY: moving.gridY, snapped: true);
    }
    final yOnly = moving.copyWith(gridY: y);
    if (!_collidesWithOthers(yOnly, furniture)) {
      return LayoutMoveResult(gridX: moving.gridX, gridY: y, snapped: true);
    }

    return LayoutMoveResult(
      gridX: moving.gridX,
      gridY: moving.gridY,
      blocked: true,
      snapped: true,
    );
  }

  /// 90° snap rotate: swaps width/height and recenters within room bounds.
  /// If the centered pose collides, searches nearby snapped cells so a desk
  /// next to a chair can still turn instead of only flipping the facing arrow.
  static LayoutMoveResult resolveRotate({
    required String id,
    required double deltaDegrees,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    FurnitureItem? moving;
    for (final f in furniture) {
      if (f.id == id) {
        moving = f;
        break;
      }
    }
    if (moving == null) {
      return const LayoutMoveResult(gridX: 0, gridY: 0, blocked: true);
    }

    final steps = (deltaDegrees / 90).round();
    if (steps == 0) {
      return LayoutMoveResult(gridX: moving.gridX, gridY: moving.gridY);
    }

    final swap = steps.abs() % 2 == 1;
    final nextW = swap ? moving.height : moving.width;
    final nextH = swap ? moving.width : moving.height;
    final cx = moving.gridX + moving.width / 2;
    final cy = moving.gridY + moving.height / 2;
    final maxX = (gridCols - nextW).clamp(0.0, gridCols.toDouble());
    final maxY = (gridRows - nextH).clamp(0.0, gridRows.toDouble());

    bool fits(double x, double y) {
      final candidate = moving!.copyWith(
        gridX: x,
        gridY: y,
        width: nextW,
        height: nextH,
        yawDegrees: ((moving.yawDegrees + steps * 90) % 360 + 360) % 360,
      );
      if (_skipsCollision(candidate)) return true;
      return !_collidesWithOthers(candidate, furniture);
    }

    // Prefer keeping the center, then spiral out on the snap grid.
    final preferredX = snap(cx - nextW / 2).clamp(0.0, maxX);
    final preferredY = snap(cy - nextH / 2).clamp(0.0, maxY);
    if (fits(preferredX, preferredY)) {
      return LayoutMoveResult(gridX: preferredX, gridY: preferredY, snapped: true);
    }

    for (int ring = 1; ring <= 12; ring++) {
      for (int iy = -ring; iy <= ring; iy++) {
        for (int ix = -ring; ix <= ring; ix++) {
          if (ix.abs() != ring && iy.abs() != ring) continue;
          final x = snap(preferredX + ix * snapStep).clamp(0.0, maxX);
          final y = snap(preferredY + iy * snapStep).clamp(0.0, maxY);
          if (fits(x, y)) {
            return LayoutMoveResult(gridX: x, gridY: y, snapped: true);
          }
        }
      }
    }

    return LayoutMoveResult(
      gridX: moving.gridX,
      gridY: moving.gridY,
      blocked: true,
    );
  }

  static FurnitureItem? rotatedItem({
    required String id,
    required double deltaDegrees,
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    FurnitureItem? moving;
    for (final f in furniture) {
      if (f.id == id) {
        moving = f;
        break;
      }
    }
    if (moving == null) return null;

    final steps = (deltaDegrees / 90).round();
    if (steps == 0) return moving;

    final swap = steps.abs() % 2 == 1;
    final nextW = swap ? moving.height : moving.width;
    final nextH = swap ? moving.width : moving.height;
    final resolved = resolveRotate(
      id: id,
      deltaDegrees: deltaDegrees,
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    if (resolved.blocked) return null;

    return moving.copyWith(
      gridX: resolved.gridX,
      gridY: resolved.gridY,
      width: nextW,
      height: nextH,
      yawDegrees: ((moving.yawDegrees + steps * 90) % 360 + 360) % 360,
    );
  }

  /// First free snapped cell, preferring walls (good for fans / lamps).
  static ({double gridX, double gridY})? findEmptyCell({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    double width = 1,
    double height = 1,
  }) {
    ({double gridX, double gridY, double wall})? best;
    for (double y = 0; y <= gridRows - height + 0.001; y += snapStep) {
      for (double x = 0; x <= gridCols - width + 0.001; x += snapStep) {
        final probe = FurnitureItem(
          id: '_empty_probe',
          name: 'probe',
          iconName: 'fan',
          category: 'neutral',
          gridX: x,
          gridY: y,
          width: width,
          height: height,
        );
        if (_collidesWithOthers(probe, furniture)) continue;
        final wall = [
          x,
          y,
          gridCols - width - x,
          gridRows - height - y,
        ].reduce((a, b) => a < b ? a : b);
        if (best == null || wall < best.wall) {
          best = (gridX: x, gridY: y, wall: wall);
        }
      }
    }
    if (best == null) return null;
    return (gridX: best.gridX, gridY: best.gridY);
  }

  static bool _collidesWithOthers(FurnitureItem candidate, List<FurnitureItem> furniture) {
    for (final other in furniture) {
      if (other.id == candidate.id) continue;
      if (_pairBlocks(candidate, other, furniture)) return true;
    }
    return false;
  }

  /// True when two items fight for the same space. Desktop items on a desk
  /// ignore the desk (and the floor under it) but still bump each other.
  static bool blocks(FurnitureItem a, FurnitureItem b, List<FurnitureItem> furniture) =>
      _pairBlocks(a, b, furniture);

  /// True when two items fight for the same space. Desktop items on a desk
  /// ignore the desk (and the floor under it) but still bump each other.
  static bool _pairBlocks(FurnitureItem a, FurnitureItem b, List<FurnitureItem> furniture) {
    if (!overlaps(a, b)) return false;
    if (skipsFloorOccupancy(a) && !SurfaceMounts.isDeskTopItem(a)) return false;
    if (skipsFloorOccupancy(b) && !SurfaceMounts.isDeskTopItem(b)) return false;

    final hostA = SurfaceMounts.hostUnder(a, furniture);
    final hostB = SurfaceMounts.hostUnder(b, furniture);
    if (hostA != null) {
      if (b.id == hostA.id) return false;
      if (SurfaceMounts.isDeskTopItem(b) && hostB?.id == hostA.id) return true;
      return false;
    }
    if (hostB != null) {
      if (a.id == hostB.id) return false;
      if (SurfaceMounts.isDeskTopItem(a) && hostA?.id == hostB.id) return true;
      return false;
    }
    return true;
  }

  static List<LayoutConflict> findConflicts({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
  }) {
    final conflicts = <LayoutConflict>[];

    for (int i = 0; i < furniture.length; i++) {
      for (int j = i + 1; j < furniture.length; j++) {
        final a = furniture[i];
        final b = furniture[j];
        if (!_pairBlocks(a, b, furniture)) continue;
        conflicts.add(
          LayoutConflict(
            kind: LayoutConflictKind.overlap,
            message: '${a.name} overlaps ${b.name}',
            itemIds: [a.id, b.id],
          ),
        );
      }
    }

    for (final opening in furniture.where(_isOpening)) {
      for (final other in furniture) {
        if (other.id == opening.id) continue;
        if (_skipsCollision(other)) continue;
        if (!overlaps(opening, other)) continue;
        conflicts.add(
          LayoutConflict(
            kind: LayoutConflictKind.blockedOpening,
            message: '${other.name} blocks ${opening.name}',
            itemIds: [other.id, opening.id],
          ),
        );
      }

      // Soft clearance: keep ~0.75 cell free inward from wall openings.
      final inwardY = opening.gridY <= 0.35
          ? opening.gridY + opening.height
          : opening.gridY >= gridRows - opening.height - 0.35
              ? opening.gridY - 0.75
              : null;
      if (inwardY != null) {
        final zone = FurnitureItem(
          id: '_clearance',
          name: 'Clearance',
          iconName: 'door',
          category: 'neutral',
          gridX: opening.gridX,
          gridY: inwardY,
          width: opening.width,
          height: 0.75,
        );
        for (final other in furniture) {
          if (other.id == opening.id) continue;
          if (_skipsCollision(other)) continue;
          if (!overlaps(zone, other)) continue;
          conflicts.add(
            LayoutConflict(
              kind: LayoutConflictKind.tightClearance,
              message: '${other.name} sits too close to ${opening.name}',
              itemIds: [other.id, opening.id],
            ),
          );
        }
      }
    }

    return conflicts;
  }
}
