// lib/services/ergonomics_simulator.dart
// Comfort metrics + frequent walk paths for Bench / Auto-Rig.
import 'dart:math';
import '../models/room_model.dart';

class ErgonomicsMetrics {
  final double comfortScore; // 0-100 overall
  final double chairClearance; // 0-1 pull-back space behind chair
  final double deskAlign; // 0-1 chair centered on desk
  final double reachScore; // 0-1 gear within seated reach
  final double aisleScore; // 0-1 work-zone aisle not blocked
  final double pathScore; // 0-1 frequent routes stay clear / short
  final double conflictRatio; // 0-1 overlaps / jammed clearances

  const ErgonomicsMetrics({
    required this.comfortScore,
    required this.chairClearance,
    required this.deskAlign,
    required this.reachScore,
    required this.aisleScore,
    required this.pathScore,
    required this.conflictRatio,
  });
}

class ErgonomicsZone {
  final double minX, minZ, maxX, maxZ;
  final String kind; // pullback | aisle | conflict
  final double severity; // 0-1

  const ErgonomicsZone({
    required this.minX,
    required this.minZ,
    required this.maxX,
    required this.maxZ,
    required this.kind,
    required this.severity,
  });
}

class ErgonomicsLink {
  final double x0, z0, x1, z1;
  final String kind; // align | reach
  final bool ok;

  const ErgonomicsLink({
    required this.x0,
    required this.z0,
    required this.x1,
    required this.z1,
    required this.kind,
    required this.ok,
  });
}

/// Seated reach envelope drawn as a circle (not a square AABB).
class ErgonomicsReachCircle {
  final double x;
  final double z;
  final double radius;

  const ErgonomicsReachCircle({
    required this.x,
    required this.z,
    required this.radius,
  });
}

/// High-traffic circulation corridor between two anchors.
class ErgonomicsPath {
  final String fromId;
  final String toId;
  final String label;
  final double frequency; // 0-1 relative traffic
  final List<({double x, double z})> points;
  final bool clear;
  final double detourRatio; // path / straight; 1 = ideal

  const ErgonomicsPath({
    required this.fromId,
    required this.toId,
    required this.label,
    required this.frequency,
    required this.points,
    required this.clear,
    required this.detourRatio,
  });
}

class ErgonomicsSimSnapshot {
  final double roomWidth;
  final double roomDepth;
  final List<FurnitureItem> furniture;
  final List<ErgonomicsZone> zones;
  final List<ErgonomicsLink> links;
  final List<ErgonomicsPath> paths;
  final ErgonomicsReachCircle? reachCircle;
  final ErgonomicsMetrics metrics;
  final bool optimized;

  const ErgonomicsSimSnapshot({
    required this.roomWidth,
    required this.roomDepth,
    required this.furniture,
    required this.zones,
    required this.links,
    required this.paths,
    required this.reachCircle,
    required this.metrics,
    required this.optimized,
  });
}

class ErgonomicsSimulator {
  static const roomWidth = 6.0;
  static const roomDepth = 8.0;

  /// Ideal chair offset behind desk front edge (grid cells ≈ meters).
  static const idealChairGap = 0.95;
  static const minPullback = 0.85;
  static const reachRadius = 1.35;

  static const _pathGridCols = 24;
  static const _pathGridRows = 32;

  static ErgonomicsSimSnapshot build({
    required List<FurnitureItem> furniture,
    required bool optimized,
  }) {
    final desk = _find(furniture, 'desk');
    final chair = _find(furniture, 'chair');
    final zones = <ErgonomicsZone>[];
    final links = <ErgonomicsLink>[];
    ErgonomicsReachCircle? reachCircle;

    var chairClearance = 0.35;
    var deskAlign = 0.35;
    var reachScore = 0.35;
    var aisleScore = 0.45;
    var conflictRatio = 0.0;

    if (desk != null && chair != null) {
      final deskCx = desk.gridX + desk.width * 0.5;
      final deskFront = desk.gridY + desk.height;
      final chairCx = chair.gridX + chair.width * 0.5;
      final chairCz = chair.gridY + chair.height * 0.5;

      final lateral = (chairCx - deskCx).abs();
      deskAlign = (1.0 - (lateral / 1.1).clamp(0.0, 1.0));
      final gap = chair.gridY - deskFront;
      final gapScore = 1.0 - ((gap - idealChairGap).abs() / 1.1).clamp(0.0, 1.0);
      deskAlign = (deskAlign * 0.55 + gapScore * 0.45).clamp(0.0, 1.0);

      links.add(
        ErgonomicsLink(
          x0: deskCx,
          z0: desk.gridY + desk.height * 0.5,
          x1: chairCx,
          z1: chairCz,
          kind: 'align',
          ok: deskAlign > 0.55,
        ),
      );

      final pullMinZ = chair.gridY + chair.height;
      final pullMaxZ = (pullMinZ + minPullback).clamp(0.0, roomDepth);
      final pullMinX = chair.gridX - 0.15;
      final pullMaxX = chair.gridX + chair.width + 0.15;
      final blockers = furniture.where((f) {
        if (f.id == 'chair' || f.id == 'desk' || f.id == 'window' || f.id == 'lamp') {
          return false;
        }
        return _rectsOverlap(
          pullMinX,
          pullMinZ,
          pullMaxX,
          pullMaxZ,
          f.gridX,
          f.gridY,
          f.gridX + f.width,
          f.gridY + f.height,
        );
      }).toList();

      final freeDepth = blockers.isEmpty
          ? minPullback
          : blockers
              .map((f) => max(0.0, f.gridY - pullMinZ))
              .fold<double>(minPullback, min);
      chairClearance = (freeDepth / minPullback).clamp(0.0, 1.0);
      zones.add(
        ErgonomicsZone(
          minX: pullMinX.clamp(0.0, roomWidth),
          minZ: pullMinZ.clamp(0.0, roomDepth),
          maxX: pullMaxX.clamp(0.0, roomWidth),
          maxZ: pullMaxZ,
          kind: 'pullback',
          severity: 1.0 - chairClearance,
        ),
      );

      reachCircle = ErgonomicsReachCircle(x: chairCx, z: chairCz, radius: reachRadius);

      final gear = furniture.where((f) {
        final id = f.id.toLowerCase();
        return id == 'pc' || id == 'monitor' || id == 'lamp';
      });
      if (gear.isEmpty) {
        reachScore = 0.5;
      } else {
        var sum = 0.0;
        for (final g in gear) {
          final gx = g.gridX + g.width * 0.5;
          final gz = g.gridY + g.height * 0.5;
          final dist = sqrt(pow(gx - chairCx, 2) + pow(gz - chairCz, 2));
          final ok = dist <= reachRadius * (optimized ? 1.05 : 1.0);
          sum += (1.0 - (dist / (reachRadius * 1.6)).clamp(0.0, 1.0));
          links.add(
            ErgonomicsLink(
              x0: chairCx,
              z0: chairCz,
              x1: gx,
              z1: gz,
              kind: 'reach',
              ok: ok,
            ),
          );
        }
        reachScore = (sum / gear.length).clamp(0.0, 1.0);
      }

      final aisleMinX = desk.gridX + desk.width + 0.05;
      final aisleMaxX = (aisleMinX + 0.9).clamp(0.0, roomWidth);
      final aisleMinZ = desk.gridY;
      final aisleMaxZ = (deskFront + 1.4).clamp(0.0, roomDepth);
      final aisleBlockers = furniture.where((f) {
        if (f.id == 'desk' || f.id == 'chair' || f.id == 'window' || f.id == 'lamp' || f.id == 'monitor') {
          return false;
        }
        if (f.id == 'pc' && f.gridX + f.width <= desk.gridX + 0.05) return false;
        return _rectsOverlap(
          aisleMinX,
          aisleMinZ,
          aisleMaxX,
          aisleMaxZ,
          f.gridX,
          f.gridY,
          f.gridX + f.width,
          f.gridY + f.height,
        );
      }).toList();
      aisleScore = (1.0 - aisleBlockers.length * 0.35).clamp(0.0, 1.0);
      zones.add(
        ErgonomicsZone(
          minX: aisleMinX,
          minZ: aisleMinZ,
          maxX: aisleMaxX,
          maxZ: aisleMaxZ,
          kind: 'aisle',
          severity: 1.0 - aisleScore,
        ),
      );
    }

    var conflictCount = 0;
    var pairs = 0;
    for (int i = 0; i < furniture.length; i++) {
      for (int j = i + 1; j < furniture.length; j++) {
        final a = furniture[i];
        final b = furniture[j];
        if (a.id == 'window' || b.id == 'window' || a.id == 'door' || b.id == 'door') continue;
        pairs++;
        if (_overlaps(a, b)) {
          conflictCount++;
          zones.add(
            ErgonomicsZone(
              minX: max(a.gridX, b.gridX),
              minZ: max(a.gridY, b.gridY),
              maxX: min(a.gridX + a.width, b.gridX + b.width),
              maxZ: min(a.gridY + a.height, b.gridY + b.height),
              kind: 'conflict',
              severity: 1.0,
            ),
          );
        }
      }
    }
    conflictRatio = pairs == 0 ? 0.0 : (conflictCount / pairs).clamp(0.0, 1.0);

    final paths = _buildFrequentPaths(furniture);
    var pathScore = 0.55;
    if (paths.isNotEmpty) {
      var weighted = 0.0;
      var weightSum = 0.0;
      for (final p in paths) {
        final quality = p.clear
            ? (1.0 - ((p.detourRatio - 1.0) / 1.8).clamp(0.0, 1.0))
            : 0.12;
        weighted += quality * p.frequency;
        weightSum += p.frequency;
      }
      pathScore = weightSum == 0 ? 0.55 : (weighted / weightSum).clamp(0.0, 1.0);
    }

    final comfort = (
            chairClearance * 22 +
            deskAlign * 20 +
            reachScore * 16 +
            aisleScore * 12 +
            pathScore * 22 +
            (1 - conflictRatio) * 8)
        .clamp(0.0, 100.0);

    return ErgonomicsSimSnapshot(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      furniture: List.unmodifiable(furniture),
      zones: zones,
      links: links,
      paths: paths,
      reachCircle: reachCircle,
      metrics: ErgonomicsMetrics(
        comfortScore: comfort,
        chairClearance: chairClearance,
        deskAlign: deskAlign,
        reachScore: reachScore,
        aisleScore: aisleScore,
        pathScore: pathScore,
        conflictRatio: conflictRatio,
      ),
      optimized: optimized,
    );
  }

  static List<ErgonomicsPath> _buildFrequentPaths(List<FurnitureItem> furniture) {
    final routes = <({String from, String to, String label, double freq})>[
      (from: 'bed', to: 'pc', label: 'Bed → PC', freq: 1.0),
      (from: 'bed', to: 'desk', label: 'Bed → Desk', freq: 0.9),
      (from: 'door', to: 'desk', label: 'Door → Desk', freq: 0.85),
      (from: 'chair', to: 'bed', label: 'Chair → Bed', freq: 0.65),
      (from: 'desk', to: 'shelf', label: 'Desk → Storage', freq: 0.45),
    ];

    final blocked = _occupancy(furniture);
    final out = <ErgonomicsPath>[];

    for (final route in routes) {
      final a = _find(furniture, route.from);
      final b = _find(furniture, route.to);
      if (a == null || b == null) continue;

      final start = _edgePoint(a, toward: b);
      final end = _edgePoint(b, toward: a);
      final straight = sqrt(pow(end.x - start.x, 2) + pow(end.z - start.z, 2));
      final found = _findPath(start, end, blocked, ignoreIds: {a.id, b.id}, furniture: furniture);

      if (found == null) {
        out.add(
          ErgonomicsPath(
            fromId: a.id,
            toId: b.id,
            label: route.label,
            frequency: route.freq,
            points: [start, end],
            clear: false,
            detourRatio: 3.0,
          ),
        );
        continue;
      }

      final len = _polylineLength(found);
      out.add(
        ErgonomicsPath(
          fromId: a.id,
          toId: b.id,
          label: route.label,
          frequency: route.freq,
          points: found,
          clear: true,
          detourRatio: straight < 0.15 ? 1.0 : (len / straight).clamp(1.0, 4.0),
        ),
      );
    }
    return out;
  }

  static ({double x, double z}) _edgePoint(FurnitureItem item, {required FurnitureItem toward}) {
    final cx = item.gridX + item.width * 0.5;
    final cz = item.gridY + item.height * 0.5;
    final tx = toward.gridX + toward.width * 0.5;
    final tz = toward.gridY + toward.height * 0.5;
    final dx = tx - cx;
    final dz = tz - cz;
    final mag = sqrt(dx * dx + dz * dz);
    if (mag < 1e-4) return (x: cx, z: cz);
    // Step just outside the footprint toward the destination.
    final nx = dx / mag;
    final nz = dz / mag;
    final pad = 0.12;
    return (
      x: (cx + nx * (item.width * 0.5 + pad)).clamp(0.05, roomWidth - 0.05),
      z: (cz + nz * (item.height * 0.5 + pad)).clamp(0.05, roomDepth - 0.05),
    );
  }

  static List<bool> _occupancy(List<FurnitureItem> furniture) {
    final cells = List<bool>.filled(_pathGridCols * _pathGridRows, false);
    final cellW = roomWidth / _pathGridCols;
    final cellH = roomDepth / _pathGridRows;
    for (final f in furniture) {
      final id = f.id.toLowerCase();
      if (id.contains('window') || id.contains('door') || id == 'lamp') continue;
      final x0 = (f.gridX / cellW).floor().clamp(0, _pathGridCols - 1);
      final z0 = (f.gridY / cellH).floor().clamp(0, _pathGridRows - 1);
      final x1 = ((f.gridX + f.width) / cellW).ceil().clamp(0, _pathGridCols);
      final z1 = ((f.gridY + f.height) / cellH).ceil().clamp(0, _pathGridRows);
      for (int z = z0; z < z1; z++) {
        for (int x = x0; x < x1; x++) {
          cells[x + _pathGridCols * z] = true;
        }
      }
    }
    return cells;
  }

  static List<({double x, double z})>? _findPath(
    ({double x, double z}) start,
    ({double x, double z}) end,
    List<bool> blocked, {
    required Set<String> ignoreIds,
    required List<FurnitureItem> furniture,
  }) {
    // Soften occupancy for path endpoints' furniture so routes can leave/enter.
    final soft = List<bool>.from(blocked);
    final cellW = roomWidth / _pathGridCols;
    final cellH = roomDepth / _pathGridRows;
    for (final f in furniture) {
      if (!ignoreIds.contains(f.id)) continue;
      final x0 = (f.gridX / cellW).floor().clamp(0, _pathGridCols - 1);
      final z0 = (f.gridY / cellH).floor().clamp(0, _pathGridRows - 1);
      final x1 = ((f.gridX + f.width) / cellW).ceil().clamp(0, _pathGridCols);
      final z1 = ((f.gridY + f.height) / cellH).ceil().clamp(0, _pathGridRows);
      for (int z = z0; z < z1; z++) {
        for (int x = x0; x < x1; x++) {
          soft[x + _pathGridCols * z] = false;
        }
      }
    }

    int toCell(double x, double z) {
      final cx = (x / cellW).floor().clamp(0, _pathGridCols - 1);
      final cz = (z / cellH).floor().clamp(0, _pathGridRows - 1);
      return cx + _pathGridCols * cz;
    }

    ({double x, double z}) fromCell(int idx) {
      final cx = idx % _pathGridCols;
      final cz = idx ~/ _pathGridCols;
      return (x: (cx + 0.5) * cellW, z: (cz + 0.5) * cellH);
    }

    final startIdx = toCell(start.x, start.z);
    final endIdx = toCell(end.x, end.z);
    if (soft[startIdx]) soft[startIdx] = false;
    if (soft[endIdx]) soft[endIdx] = false;

    final prev = List<int>.filled(soft.length, -1);
    final q = <int>[startIdx];
    prev[startIdx] = startIdx;
    const dirs = [-1, 1, -_pathGridCols, _pathGridCols];

    while (q.isNotEmpty) {
      final cur = q.removeAt(0);
      if (cur == endIdx) break;
      final cx = cur % _pathGridCols;
      final cz = cur ~/ _pathGridCols;
      for (final d in dirs) {
        final next = cur + d;
        if (next < 0 || next >= soft.length) continue;
        final nx = next % _pathGridCols;
        final nz = next ~/ _pathGridCols;
        if ((nx - cx).abs() + (nz - cz).abs() != 1) continue;
        if (soft[next] || prev[next] != -1) continue;
        prev[next] = cur;
        q.add(next);
      }
    }

    if (prev[endIdx] == -1) return null;

    final cells = <int>[];
    var walk = endIdx;
    while (true) {
      cells.add(walk);
      if (walk == startIdx) break;
      walk = prev[walk];
      if (cells.length > soft.length) return null;
    }
    final points = <({double x, double z})>[start];
    for (final idx in cells.reversed) {
      points.add(fromCell(idx));
    }
    points.add(end);
    return _simplify(points);
  }

  static List<({double x, double z})> _simplify(List<({double x, double z})> pts) {
    if (pts.length <= 3) return pts;
    final out = <({double x, double z})>[pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      final a = out.last;
      final b = pts[i];
      final c = pts[i + 1];
      final abx = b.x - a.x;
      final abz = b.z - a.z;
      final bcx = c.x - b.x;
      final bcz = c.z - b.z;
      // Keep corners only (direction change).
      if ((abx * bcz - abz * bcx).abs() > 1e-6) {
        out.add(b);
      }
    }
    out.add(pts.last);
    return out;
  }

  static double _polylineLength(List<({double x, double z})> pts) {
    var len = 0.0;
    for (int i = 1; i < pts.length; i++) {
      len += sqrt(pow(pts[i].x - pts[i - 1].x, 2) + pow(pts[i].z - pts[i - 1].z, 2));
    }
    return len;
  }

  static FurnitureItem? _find(List<FurnitureItem> items, String id) {
    try {
      return items.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  static bool _overlaps(FurnitureItem a, FurnitureItem b) {
    return a.gridX < b.gridX + b.width &&
        a.gridX + a.width > b.gridX &&
        a.gridY < b.gridY + b.height &&
        a.gridY + a.height > b.gridY;
  }

  static bool _rectsOverlap(
    double ax0,
    double az0,
    double ax1,
    double az1,
    double bx0,
    double bz0,
    double bx1,
    double bz1,
  ) {
    return ax0 < bx1 && ax1 > bx0 && az0 < bz1 && az1 > bz0;
  }
}
