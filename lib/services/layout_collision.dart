// lib/services/layout_collision.dart
import '../models/room_model.dart';

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
  static const nonColliding = {'window', 'door', 'lamp'};

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

  static bool _skipsCollision(FurnitureItem f) => nonColliding.contains(f.id) || _isOpening(f);

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
    var x = snap(cx - nextW / 2);
    var y = snap(cy - nextH / 2);
    final maxX = (gridCols - nextW).clamp(0.0, gridCols.toDouble());
    final maxY = (gridRows - nextH).clamp(0.0, gridRows.toDouble());
    x = x.clamp(0.0, maxX);
    y = y.clamp(0.0, maxY);

    final candidate = moving.copyWith(
      gridX: x,
      gridY: y,
      width: nextW,
      height: nextH,
      yawDegrees: ((moving.yawDegrees + steps * 90) % 360 + 360) % 360,
    );

    if (!_skipsCollision(candidate) && _collidesWithOthers(candidate, furniture)) {
      return LayoutMoveResult(
        gridX: moving.gridX,
        gridY: moving.gridY,
        blocked: true,
      );
    }

    return LayoutMoveResult(gridX: x, gridY: y, snapped: true);
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

  static bool _collidesWithOthers(FurnitureItem candidate, List<FurnitureItem> furniture) {
    for (final other in furniture) {
      if (other.id == candidate.id) continue;
      if (_skipsCollision(other) || _skipsCollision(candidate)) continue;
      if (overlaps(candidate, other)) return true;
    }
    return false;
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
        if (_skipsCollision(a) || _skipsCollision(b)) continue;
        if (!overlaps(a, b)) continue;
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
