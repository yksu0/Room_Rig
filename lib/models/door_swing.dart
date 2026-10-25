// lib/models/door_swing.dart
// Quarter-circle door leaf swing in grid space (architectural plan symbol).
import 'dart:math' as math;

import 'room_model.dart';
import 'surface_mount.dart';

/// Inward door swing: hinge at one jamb, leaf sweeps 90° from the wall into
/// the room. Used for Orbit/Bench overlays and layout collision.
class DoorSwingGeometry {
  final double hingeX;
  final double hingeZ;

  /// Clear opening length (= swing radius) in grid cells.
  final double radius;

  /// Unit vector along the wall from hinge toward the free jamb.
  final double alongX;
  final double alongZ;

  /// Unit vector from the wall into the room.
  final double inwardX;
  final double inwardZ;

  const DoorSwingGeometry({
    required this.hingeX,
    required this.hingeZ,
    required this.radius,
    required this.alongX,
    required this.alongZ,
    required this.inwardX,
    required this.inwardZ,
  });

  /// Builds swing geometry for a door on its wall span, or null if not a door.
  static DoorSwingGeometry? of(
    FurnitureItem item, {
    required int gridCols,
    required int gridRows,
  }) {
    if (!SurfaceMounts.isDoor(item)) return null;
    final mount = SurfaceMounts.of(
      item,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    final span = mount.span;
    if (span == null) return null;
    return fromSpan(span);
  }

  /// Hinge at the span start jamb; leaf sweeps from along-wall to inward.
  static DoorSwingGeometry fromSpan(WallSpan span) {
    final len = span.length;
    final radius = len <= 1e-6 ? 1.0 : len;
    return DoorSwingGeometry(
      hingeX: span.x0,
      hingeZ: span.z0,
      radius: radius,
      alongX: (span.x1 - span.x0) / radius,
      alongZ: (span.z1 - span.z0) / radius,
      inwardX: span.inwardX,
      inwardZ: span.inwardZ,
    );
  }

  /// Point on the circular arc at [t] in 0..1 (θ = 0 closed … π/2 open).
  (double x, double z) pointAt(double t) {
    final angle = t.clamp(0.0, 1.0) * (math.pi / 2);
    final c = math.cos(angle);
    final s = math.sin(angle);
    return (
      hingeX + (alongX * c + inwardX * s) * radius,
      hingeZ + (alongZ * c + inwardZ * s) * radius,
    );
  }

  /// Dense samples along the true quarter-circle in grid XZ.
  List<(double x, double z)> arcPoints({int steps = 24}) {
    final n = steps < 2 ? 2 : steps;
    return [for (var i = 0; i <= n; i++) pointAt(i / n)];
  }

  /// Axis-aligned bounds of the quarter-disk (conservative collision volume).
  ({double minX, double minZ, double maxX, double maxZ}) get bounds {
    var minX = hingeX;
    var maxX = hingeX;
    var minZ = hingeZ;
    var maxZ = hingeZ;
    void include(double x, double z) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }

    include(hingeX + alongX * radius, hingeZ + alongZ * radius);
    include(hingeX + inwardX * radius, hingeZ + inwardZ * radius);
    // Mid-arc (45°) covers the quarter-disk extremum on the diagonal.
    final mid = pointAt(0.5);
    include(mid.$1, mid.$2);
    return (minX: minX, minZ: minZ, maxX: maxX, maxZ: maxZ);
  }

  /// True when [item]'s floor AABB intersects the quarter-disk swing.
  bool overlapsItem(FurnitureItem item) {
    final b = bounds;
    final ix0 = item.gridX;
    final iy0 = item.gridY;
    final ix1 = item.gridX + item.width;
    final iy1 = item.gridY + item.height;
    // Broad phase: AABB of swing square vs item.
    if (ix1 <= b.minX || ix0 >= b.maxX || iy1 <= b.minZ || iy0 >= b.maxZ) {
      return false;
    }
    // Narrow phase: any item corner inside the disk sector, or hinge/arc in item,
    // or item center inside sector.
    bool inSector(double x, double z) {
      final dx = x - hingeX;
      final dz = z - hingeZ;
      final distSq = dx * dx + dz * dz;
      if (distSq > radius * radius + 1e-6) return false;
      // Dot with along and inward must both be >= 0 (same quadrant as the sweep).
      final along = dx * alongX + dz * alongZ;
      final inward = dx * inwardX + dz * inwardZ;
      return along >= -1e-6 && inward >= -1e-6;
    }

    if (inSector(ix0, iy0) ||
        inSector(ix1, iy0) ||
        inSector(ix0, iy1) ||
        inSector(ix1, iy1) ||
        inSector((ix0 + ix1) * 0.5, (iy0 + iy1) * 0.5)) {
      return true;
    }
    // Arc samples piercing the footprint.
    for (final p in arcPoints(steps: 16)) {
      if (p.$1 >= ix0 && p.$1 <= ix1 && p.$2 >= iy0 && p.$2 <= iy1) return true;
    }
    // Closed leaf (along wall) or open leaf (inward) segment through the item.
    if (_segmentHitsAabb(
          hingeX,
          hingeZ,
          hingeX + alongX * radius,
          hingeZ + alongZ * radius,
          ix0,
          iy0,
          ix1,
          iy1,
        ) ||
        _segmentHitsAabb(
          hingeX,
          hingeZ,
          hingeX + inwardX * radius,
          hingeZ + inwardZ * radius,
          ix0,
          iy0,
          ix1,
          iy1,
        )) {
      return true;
    }
    return false;
  }

  static bool _segmentHitsAabb(
    double x0,
    double z0,
    double x1,
    double z1,
    double minX,
    double minZ,
    double maxX,
    double maxZ,
  ) {
    // Liang–Barsky style clamp.
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = x1 - x0;
    final dz = z1 - z0;

    bool clip(double p, double q) {
      if (p.abs() < 1e-12) return q >= 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clip(-dx, x0 - minX)) return false;
    if (!clip(dx, maxX - x0)) return false;
    if (!clip(-dz, z0 - minZ)) return false;
    if (!clip(dz, maxZ - z0)) return false;
    return t0 <= t1;
  }
}
