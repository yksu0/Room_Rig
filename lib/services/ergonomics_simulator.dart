// lib/services/ergonomics_simulator.dart
// Comfort metrics + frequent walk paths for Bench / Auto-Rig.
import 'dart:math';
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'comfort_heuristics.dart';
import 'layout_collision.dart';

class ErgonomicsMetrics {
  final double comfortScore; // 0-100 overall
  final double chairClearance; // 0-1 pull-back space behind chair
  final double deskAlign; // 0-1 chair centered on desk
  final double reachScore; // 0-1 gear within seated reach
  final double aisleScore; // 0-1 work-zone aisle not blocked
  final double pathScore; // 0-1 frequent routes stay clear / short / few turns
  /// 0-1: seated user can see the door (prospect–refuge preference).
  final double doorProspect;
  /// 0-1: bed not in the door's straight inbound view (sleep privacy).
  final double bedPrivacy;
  final double conflictRatio; // 0-1 overlaps / jammed clearances

  const ErgonomicsMetrics({
    required this.comfortScore,
    required this.chairClearance,
    required this.deskAlign,
    required this.reachScore,
    required this.aisleScore,
    required this.pathScore,
    this.doorProspect = 0.55,
    this.bedPrivacy = 0.6,
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
  /// Corner count on the walked route — fewer turns = less twist for frequent trips.
  final int turnCount;

  const ErgonomicsPath({
    required this.fromId,
    required this.toId,
    required this.label,
    required this.frequency,
    required this.points,
    required this.clear,
    required this.detourRatio,
    this.turnCount = 0,
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
  /// Matches [ComfortHeuristics.chairPullbackMeters] (practice clearance).
  static const idealChairGap = ComfortHeuristics.chairPullbackMeters;
  static const minPullback = 0.85;
  static const reachRadius = 1.35;

  static const _pathGridCols = 24;
  static const _pathGridRows = 32;

  /// [optimized] only styles the painter ramps; every metric comes from
  /// [furniture] alone.
  static ErgonomicsSimSnapshot build({
    required List<FurnitureItem> furniture,
    required bool optimized,
  }) {
    final desk = _findKind(furniture, _ErgoKind.desk);
    final chair = _findKind(furniture, _ErgoKind.chair);
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
      final deskCz = desk.gridY + desk.height * 0.5;
      final chairCx = chair.gridX + chair.width * 0.5;
      final chairCz = chair.gridY + chair.height * 0.5;

      // Lateral align + pull-back gap work for any chair side of the desk.
      final dx = chairCx - deskCx;
      final dz = chairCz - deskCz;
      final alongX = dx.abs() >= dz.abs();
      final lateral = alongX ? dz.abs() : dx.abs();
      final gap = alongX
          ? dx.abs() - desk.width * 0.5 - chair.width * 0.5
          : dz.abs() - desk.height * 0.5 - chair.height * 0.5;
      deskAlign = (1.0 - (lateral / 1.1).clamp(0.0, 1.0));
      final gapScore = 1.0 - ((gap - idealChairGap).abs() / 1.1).clamp(0.0, 1.0);
      deskAlign = (deskAlign * 0.55 + gapScore * 0.45).clamp(0.0, 1.0);

      links.add(
        ErgonomicsLink(
          x0: deskCx,
          z0: deskCz,
          x1: chairCx,
          z1: chairCz,
          kind: 'align',
          ok: deskAlign > 0.55,
        ),
      );

      // Pull-back zone: behind the chair, opposite the desk.
      final awayX = alongX ? (dx >= 0 ? 1.0 : -1.0) : 0.0;
      final awayZ = alongX ? 0.0 : (dz >= 0 ? 1.0 : -1.0);
      final pullMinX = alongX
          ? (awayX > 0 ? chair.gridX + chair.width : chair.gridX - minPullback)
          : chair.gridX - 0.15;
      final pullMaxX = alongX
          ? (awayX > 0 ? chair.gridX + chair.width + minPullback : chair.gridX)
          : chair.gridX + chair.width + 0.15;
      final pullMinZ = alongX
          ? chair.gridY - 0.15
          : (awayZ > 0 ? chair.gridY + chair.height : chair.gridY - minPullback);
      final pullMaxZ = alongX
          ? chair.gridY + chair.height + 0.15
          : (awayZ > 0 ? chair.gridY + chair.height + minPullback : chair.gridY);

      final blockers = furniture.where((f) {
        if (f.id == chair.id || f.id == desk.id) return false;
        if (LayoutCollision.skipsFloorOccupancy(f)) return false;
        if (SurfaceMounts.isDeskTopItem(f)) return false;
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
          : (alongX
              ? blockers
                  .map((f) => awayX > 0
                      ? max(0.0, f.gridX - (chair.gridX + chair.width))
                      : max(0.0, chair.gridX - (f.gridX + f.width)))
                  .fold<double>(minPullback, min)
              : blockers
                  .map((f) => awayZ > 0
                      ? max(0.0, f.gridY - (chair.gridY + chair.height))
                      : max(0.0, chair.gridY - (f.gridY + f.height)))
                  .fold<double>(minPullback, min));
      chairClearance = (freeDepth / minPullback).clamp(0.0, 1.0);
      zones.add(
        ErgonomicsZone(
          minX: pullMinX.clamp(0.0, roomWidth),
          minZ: pullMinZ.clamp(0.0, roomDepth),
          maxX: pullMaxX.clamp(0.0, roomWidth),
          maxZ: pullMaxZ.clamp(0.0, roomDepth),
          kind: 'pullback',
          severity: 1.0 - chairClearance,
        ),
      );

      reachCircle = ErgonomicsReachCircle(x: chairCx, z: chairCz, radius: reachRadius);

      final gear = furniture.where(_isReachGear);
      if (gear.isEmpty) {
        reachScore = 0.5;
      } else {
        var sum = 0.0;
        for (final g in gear) {
          final gx = g.gridX + g.width * 0.5;
          final gz = g.gridY + g.height * 0.5;
          final dist = sqrt(pow(gx - chairCx, 2) + pow(gz - chairCz, 2));
          final ok = dist <= reachRadius;
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

      // Side aisle next to the desk, perpendicular to the chair approach.
      final aisleMinX = alongX
          ? desk.gridX
          : desk.gridX + desk.width + 0.05;
      final aisleMaxX = alongX
          ? desk.gridX + desk.width
          : (desk.gridX + desk.width + 0.9).clamp(0.0, roomWidth);
      final aisleMinZ = alongX
          ? desk.gridY + desk.height + 0.05
          : desk.gridY;
      final aisleMaxZ = alongX
          ? (desk.gridY + desk.height + 1.4).clamp(0.0, roomDepth)
          : (desk.gridY + desk.height);
      final aisleBlockers = furniture.where((f) {
        if (f.id == desk.id || f.id == chair.id) return false;
        if (LayoutCollision.skipsFloorOccupancy(f)) return false;
        if (SurfaceMounts.isDeskTopItem(f)) return false;
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
        if (LayoutCollision.skipsFloorOccupancy(a) && !SurfaceMounts.isDeskTopItem(a)) {
          continue;
        }
        if (LayoutCollision.skipsFloorOccupancy(b) && !SurfaceMounts.isDeskTopItem(b)) {
          continue;
        }
        pairs++;
        if (LayoutCollision.blocks(a, b, furniture)) {
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
        // Detour + turn count: frequent routes should be short and not zigzag.
        final detourQ = 1.0 - ((p.detourRatio - 1.0) / 1.8).clamp(0.0, 1.0);
        final turnQ = 1.0 - (p.turnCount / 5.0).clamp(0.0, 1.0);
        final quality = p.clear ? (detourQ * 0.65 + turnQ * 0.35) : 0.12;
        weighted += quality * p.frequency;
        weightSum += p.frequency;
      }
      pathScore = weightSum == 0 ? 0.55 : (weighted / weightSum).clamp(0.0, 1.0);
    }

    final door = _findKind(furniture, _ErgoKind.door);
    final bed = _findKind(furniture, _ErgoKind.bed);
    final doorProspect = ComfortHeuristics.doorProspectScore(
      chair: chair,
      desk: desk,
      door: door,
    );
    final bedPrivacy = ComfortHeuristics.bedPrivacyFromDoor(
      bed: bed,
      door: door,
      gridCols: roomWidth.round(),
      gridRows: roomDepth.round(),
    );

    // Weights track what a person notices: clear pull-back, short walks with
    // fewer twists, gear in reach, entry visibility, and sleep-zone privacy.
    final comfort = (
            chairClearance * 16 +
            deskAlign * 14 +
            reachScore * 12 +
            aisleScore * 9 +
            pathScore * 16 +
            doorProspect * 12 +
            bedPrivacy * 11 +
            (1 - conflictRatio) * 10)
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
        doorProspect: doorProspect,
        bedPrivacy: bedPrivacy,
        conflictRatio: conflictRatio,
      ),
      optimized: optimized,
    );
  }

  /// Delegates to [ComfortHeuristics.doorProspectScore] (kept for call sites).
  static double doorVisibilityScore({
    required FurnitureItem? chair,
    required FurnitureItem? desk,
    required FurnitureItem? door,
  }) =>
      ComfortHeuristics.doorProspectScore(chair: chair, desk: desk, door: door);

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
      final a = _findKind(furniture, _kindFromRouteKey(route.from));
      final b = _findKind(furniture, _kindFromRouteKey(route.to));
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
            turnCount: 4,
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
          turnCount: _countTurns(found),
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
      if (LayoutCollision.skipsFloorOccupancy(f)) continue;
      if (SurfaceMounts.isDeskTopItem(f)) continue;
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

  /// Count direction changes — each corner is a twist people feel on frequent walks.
  static int _countTurns(List<({double x, double z})> pts) {
    if (pts.length < 3) return 0;
    var turns = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final abx = pts[i].x - pts[i - 1].x;
      final abz = pts[i].z - pts[i - 1].z;
      final bcx = pts[i + 1].x - pts[i].x;
      final bcz = pts[i + 1].z - pts[i].z;
      if ((abx * bcz - abz * bcx).abs() > 1e-4) turns++;
    }
    return turns;
  }

  static FurnitureItem? _findKind(List<FurnitureItem> items, _ErgoKind kind) {
    for (final f in items) {
      if (_matchesKind(f, kind)) return f;
    }
    return null;
  }

  static _ErgoKind _kindFromRouteKey(String key) {
    switch (key) {
      case 'bed':
        return _ErgoKind.bed;
      case 'pc':
        return _ErgoKind.pc;
      case 'desk':
        return _ErgoKind.desk;
      case 'door':
        return _ErgoKind.door;
      case 'chair':
        return _ErgoKind.chair;
      case 'shelf':
        return _ErgoKind.shelf;
      default:
        return _ErgoKind.desk;
    }
  }

  static bool _matchesKind(FurnitureItem f, _ErgoKind kind) {
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    switch (kind) {
      case _ErgoKind.desk:
        return SurfaceMounts.isDeskHost(f);
      case _ErgoKind.chair:
        return f.iconName == 'chair' || hay.contains('chair') || hay.contains('seat');
      case _ErgoKind.bed:
        return f.iconName == 'bed' || hay.contains('bed');
      case _ErgoKind.pc:
        return f.iconName == 'pc' ||
            hay.contains('pc') ||
            hay.contains('computer') ||
            hay.contains('tower');
      case _ErgoKind.door:
        return f.iconName == 'door' || hay.contains('door');
      case _ErgoKind.shelf:
        return f.iconName == 'shelf' ||
            hay.contains('shelf') ||
            hay.contains('bookcase') ||
            hay.contains('wardrobe');
    }
  }

  static bool _isReachGear(FurnitureItem f) {
    if (SurfaceMounts.isDeskTopItem(f)) return true;
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    return hay.contains('monitor') ||
        hay.contains('pc') ||
        (hay.contains('lamp') && !hay.contains('floor'));
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

enum _ErgoKind { desk, chair, bed, pc, door, shelf }
