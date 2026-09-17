// Researched furniture placement rules for every Rig catalog + upgrade SKU.
//
// Sources (practice / agency / environmental psychology — not app certification):
 // - OSHA Computer Workstations eTools: display at right angles to windows
 // - Interior clearance guides (RoomSketch3D / Layoutr / Homes & Gardens):
 //     chair pull-back ~36–48 in; bed walk side ~24 in; bed foot ~36 in;
 //     desk↔storage ~42 in; sofa↔TV viewing 1.5–2.5× diagonal; wardrobe door swing
 // - Prospect–refuge (Appleton 1975): seat/bed can see entry, not back-to-door
 // - HVAC practice: keep furniture off supply/return faces (~6–18 in)
 // - Command / sleep privacy: bed not in door's straight inbound axis
//
// Grid cells ≈ 1 m. Clearances below are in cells.
import 'dart:math' as math;

import '../models/room_model.dart';
import '../models/surface_mount.dart';

/// Where a piece wants to live after Auto-Rig.
enum PlacementZone {
  /// Fixed openings / wall fittings.
  wallFixture,

  /// Tall storage flush to a wall / corner.
  perimeterWall,

  /// Large sleep / lounge pieces along walls.
  perimeterLarge,

  /// Desk + chair + desk-tops as one cluster.
  workCluster,

  /// Desk surface only.
  deskTop,

  /// Floor appliances that need open throw / intake volume.
  openFloor,

  /// Soft accent near walls / corners (plant, floor lamp).
  accent,

  /// Ceiling plane center-ish.
  ceiling,
}

/// Honest, item-by-item arrangement knowledge used by Auto-Rig packing.
class ItemPlacementRules {
  ItemPlacementRules._();

  /// Minimum clear gap between bed AABB and desk AABB (~42 in desk↔furniture
  /// practice + workspace separation in bedroom layout guides).
  static const deskBedClearance = 1.05;

  /// Chair centered on the desk face with pull-back (see ComfortHeuristics).
  static const chairPullback = 0.95;

  /// Tall storage / wardrobe should sit within this distance of a wall.
  static const wallFlushTolerance = 0.35;

  /// Desk must hug a side wall within this distance (never mid-room).
  static const deskWallTolerance = 0.35;

  /// Exact inset when pinning a desk to a side wall (flush — not a visible gap).
  static const deskWallFlush = 0.0;

  /// Sofa ↔ TV preferred center distance (≈ 55" TV mid viewing band ~2 m).
  static const sofaTvPreferred = 2.2;

  /// Tolerance around [sofaTvPreferred] for Auto-Rig / tests.
  static const sofaTvTolerance = 0.65;

  /// Clear depth in front of a wardrobe for door swing (~door width + 0.1 m).
  static const wardrobeFrontClearance = 1.1;

  static String hay(FurnitureItem f) =>
      '${f.id} ${f.name} ${f.iconName}'.toLowerCase();

  static PlacementZone zoneFor(FurnitureItem f) {
    if (SurfaceMounts.isDoor(f) ||
        SurfaceMounts.isWindow(f) ||
        SurfaceMounts.isVent(f) ||
        SurfaceMounts.isIntake(f) ||
        SurfaceMounts.isExhaust(f) ||
        hay(f).contains('blind')) {
      return PlacementZone.wallFixture;
    }
    if (SurfaceMounts.isCeilingFixture(f) || hay(f).contains('ceiling')) {
      return PlacementZone.ceiling;
    }
    if (SurfaceMounts.isDeskTopItem(f)) return PlacementZone.deskTop;

    final h = hay(f);
    if (h.contains('chair')) return PlacementZone.workCluster;
    if (SurfaceMounts.isDeskHost(f) && !h.contains('table')) {
      return PlacementZone.workCluster;
    }
    if (h.contains('bed') || h.contains('sofa') || h.contains('couch')) {
      return PlacementZone.perimeterLarge;
    }
    if (h.contains('shelf') ||
        h.contains('book') ||
        h.contains('wardrobe') ||
        h.contains('dresser')) {
      return PlacementZone.perimeterWall;
    }
    if (h.contains('portable') ||
        h.contains('fan') ||
        h.contains('heater') ||
        h.contains('purifier')) {
      return PlacementZone.openFloor;
    }
    if (h.contains('plant') ||
        h.contains('floorlamp') ||
        h.contains('floor_lamp') ||
        h.contains('floor lamp') ||
        h.contains('mat')) {
      return PlacementZone.accent;
    }
    if (h.contains('tv') || h.contains('table')) {
      return PlacementZone.perimeterLarge;
    }
    return PlacementZone.accent;
  }

  static bool prefersWall(FurnitureItem f) {
    switch (zoneFor(f)) {
      case PlacementZone.perimeterWall:
      case PlacementZone.perimeterLarge:
      case PlacementZone.wallFixture:
      case PlacementZone.accent:
        return true;
      case PlacementZone.workCluster:
        // Desk hugs a wall; chair follows the desk (not packed mid-room alone).
        return hay(f).contains('desk') || SurfaceMounts.isDeskHost(f);
      case PlacementZone.deskTop:
      case PlacementZone.openFloor:
      case PlacementZone.ceiling:
        return false;
    }
  }

  static bool prefersInterior(FurnitureItem f) =>
      zoneFor(f) == PlacementZone.openFloor;

  /// Human-readable placement note for each SKU (catalog + upgrades).
  static String arrangementNote(String baseIdOrIcon) {
    switch (baseIdOrIcon.toLowerCase()) {
      case 'desk':
        return 'Against a wall or window-side offset; leave ~1 m behind for the chair; '
            'screens at right angles to windows (OSHA).';
      case 'chair':
        return 'Directly in front of the desk face, centered, with ~0.9–1.2 m pull-back; '
            'prefer a view toward the door (prospect–refuge).';
      case 'monitor':
      case 'monitorarm':
      case 'upg_monitor_arm':
        return 'On the desk, facing the chair; eye-height / arm reach — never on the floor.';
      case 'pc':
        return 'On or under the desk host; keep intake clear of walls when floor-standing.';
      case 'lamp':
      case 'lightbar':
      case 'upg_light_bar':
        return 'Task light on the desk surface, beside the monitor.';
      case 'cabletray':
      case 'upg_cable_tray':
        return 'Under the desk front edge.';
      case 'mat':
      case 'upg_mat':
        return 'On the floor under/just behind the chair.';
      case 'bed':
        return 'Against a solid wall, not in the door’s straight inbound view; '
            '≥24 in walk side; keep ≥~1 m clear of the desk work zone.';
      case 'sofa':
        return 'Along a wall, facing the TV / focal point; separate lounge zone from sleep.';
      case 'table':
        return 'Lounge surface near the sofa — stack TV, plant, or a small task lamp; '
            'not for bed/chair/wardrobe.';
      case 'wardrobe':
        return 'Flush to a wall/corner; leave door-swing depth in front (~door width + 0.1 m).';
      case 'shelf':
      case 'bookshelf':
        return 'Flush to a wall or corner — never floating mid-room; keep ~1 m from desk if possible.';
      case 'plant':
        return 'On the lounge table when present, else a bright corner — out of main walk paths.';
      case 'tv':
        return 'On the lounge table facing the sofa when a table exists; else a clear wall. '
            'Viewing distance ~1.5–2.5× screen diagonal.';
      case 'door':
        return 'On a wall opening; keep approach aisle clear of furniture.';
      case 'window':
        return 'On an exterior wall; desk/chair prefer side light, not square-on glare.';
      case 'ac':
        return 'High on a wall; keep throw path open; furniture off the face (~0.15–0.45 m).';
      case 'intake':
      case 'exhaust':
        return 'Wall grille; do not cover with tall storage.';
      case 'portable_ac':
        return 'Open floor volume with exhaust hose path; not jammed in a corner against walls.';
      case 'fan':
      case 'upg_fan':
        return 'Open floor aimed at the work or lounge zone; keep blades clear.';
      case 'space_heater':
      case 'heater':
        return 'Clear floor, away from bedding/curtains; not blocking HVAC returns.';
      case 'floor_lamp':
      case 'floorlamp':
      case 'upg_floor_lamp':
        return 'Beside sofa/desk reading side, near a wall — not center of circulation.';
      case 'ceiling_light':
        return 'Near room center on the ceiling plane.';
      case 'upg_purifier':
      case 'purifier':
        return 'Open floor with intake clearance; often near desk or lounge.';
      case 'upg_blinds':
      case 'smartblinds':
        return 'On the window wall for glare control.';
      default:
        return 'Place by zone: walls for storage, cluster for desk work, open floor for airflow gear.';
    }
  }

  /// True when AABBs keep at least [minGap] clear space (not overlapping).
  static bool hasClearGap(FurnitureItem a, FurnitureItem b, double minGap) {
    final gapX = a.gridX + a.width <= b.gridX
        ? b.gridX - (a.gridX + a.width)
        : (b.gridX + b.width <= a.gridX ? a.gridX - (b.gridX + b.width) : 0.0);
    final gapY = a.gridY + a.height <= b.gridY
        ? b.gridY - (a.gridY + a.height)
        : (b.gridY + b.height <= a.gridY ? a.gridY - (b.gridY + b.height) : 0.0);

    final overlapX = gapX <= 0;
    final overlapY = gapY <= 0;
    if (overlapX && overlapY) return false;
    if (overlapX) return gapY >= minGap;
    if (overlapY) return gapX >= minGap;
    return gapX >= minGap || gapY >= minGap;
  }

  /// Distance from item AABB to the nearest room wall (0 = flush).
  static double wallDistance(FurnitureItem f, int cols, int rows) {
    final left = f.gridX;
    final top = f.gridY;
    final right = cols - (f.gridX + f.width);
    final bottom = rows - (f.gridY + f.height);
    return [left, top, right, bottom].reduce((a, b) => a < b ? a : b);
  }

  /// Which side of the desk is the seating / screen work face.
  ///
  /// Prefer the **longer** desk edge that still has chair pull-back room.
  /// Side-wall desks are oriented long-along-wall first (see
  /// [LayoutOptimizerCommon]), so a west-wall desk is typically 1×2 with work
  /// face **east** (long inward edge) — not the short stub into the room.
  static String deskWorkFace(FurnitureItem desk, int gridCols, int gridRows) {
    final left = desk.gridX;
    final top = desk.gridY;
    final right = gridCols - (desk.gridX + desk.width);
    final bottom = gridRows - (desk.gridY + desk.height);
    final minClear = chairPullback * 0.75;

    final options = <({String face, double edge, double clear})>[
      (face: 'south', edge: desk.width, clear: bottom),
      (face: 'north', edge: desk.width, clear: top),
      (face: 'east', edge: desk.height, clear: right),
      (face: 'west', edge: desk.height, clear: left),
    ];

    // Viable = enough room to pull the chair out.
    var pool = options.where((o) => o.clear >= minClear).toList();
    if (pool.isEmpty) pool = List.of(options);

    pool.sort((a, b) {
      // 1) Longer edge first (user sits on the long side of the desk).
      final byEdge = b.edge.compareTo(a.edge);
      if (byEdge != 0) return byEdge;
      // 2) Then more open clearance.
      final byClear = b.clear.compareTo(a.clear);
      if (byClear != 0) return byClear;
      // 3) Stable preference: south > east > north > west.
      const rank = {'south': 0, 'east': 1, 'north': 2, 'west': 3};
      return (rank[a.face] ?? 9).compareTo(rank[b.face] ?? 9);
    });
    return pool.first.face;
  }

  /// Yaw degrees so a screen / person faces [deskWorkFace] (+Z = 0).
  static double yawFacingWorkFace(String face) {
    switch (face) {
      case 'east':
        return 90;
      case 'west':
        return 270;
      case 'north':
        return 180;
      case 'south':
      default:
        return 0;
    }
  }

  /// Stricter: chair centered on the long work face with pull-back clearance.
  /// Side seats (east/west of a freestanding north–south desk) fail.
  static bool chairOnWorkFace(
    FurnitureItem chair,
    FurnitureItem desk, {
    int? gridCols,
    int? gridRows,
  }) {
    final cx = chair.gridX + chair.width * 0.5;
    final cy = chair.gridY + chair.height * 0.5;
    final dx0 = desk.gridX;
    final dy0 = desk.gridY;
    final dx1 = desk.gridX + desk.width;
    final dy1 = desk.gridY + desk.height;

    final String face;
    if (gridCols != null && gridRows != null) {
      face = deskWorkFace(desk, gridCols, gridRows);
    } else {
      final deskCx = (dx0 + dx1) * 0.5;
      final deskCy = (dy0 + dy1) * 0.5;
      final alongX = (cx - deskCx).abs();
      final alongY = (cy - deskCy).abs();
      if (alongY >= alongX) {
        face = cy > deskCy ? 'south' : 'north';
      } else {
        face = cx > deskCx ? 'east' : 'west';
      }
    }

    bool alignedX() => cx >= dx0 - 0.4 && cx <= dx1 + 0.4;
    bool alignedY() => cy >= dy0 - 0.4 && cy <= dy1 + 0.4;
    bool gapOk(double g) => g >= 0.2 && g <= chairPullback + 0.9;

    switch (face) {
      case 'east':
        return alignedY() && gapOk(cx - dx1);
      case 'west':
        return alignedY() && gapOk(dx0 - cx);
      case 'north':
        return alignedX() && gapOk(dy0 - cy);
      case 'south':
      default:
        return alignedX() && gapOk(cy - dy1);
    }
  }

  /// Desk is flush to a left/right wall (not floating mid-room).
  static bool deskOnSideWall(FurnitureItem desk, int cols, int rows) {
    final left = desk.gridX;
    final right = cols - (desk.gridX + desk.width);
    return left <= deskWallTolerance || right <= deskWallTolerance;
  }

  /// Desk is visually flush (no noticeable gap from the wall).
  static bool deskFlushToWall(FurnitureItem desk, int cols, int rows) {
    final left = desk.gridX;
    final right = cols - (desk.gridX + desk.width);
    return left <= deskWallFlush + 0.05 || right <= deskWallFlush + 0.05;
  }

  static bool isSofa(FurnitureItem f) {
    final h = hay(f);
    return h.contains('sofa') || h.contains('couch');
  }

  static bool isTv(FurnitureItem f) {
    final h = hay(f);
    return h.contains('tv') || h.contains('television');
  }

  static bool isWardrobe(FurnitureItem f) {
    final h = hay(f);
    return h.contains('wardrobe') || h.contains('closet') || h.contains('armoire');
  }

  /// Center-to-center distance in grid cells.
  static double sofaTvCenterDistance(FurnitureItem sofa, FurnitureItem tv) {
    final sx = sofa.gridX + sofa.width * 0.5;
    final sy = sofa.gridY + sofa.height * 0.5;
    final tx = tv.gridX + tv.width * 0.5;
    final ty = tv.gridY + tv.height * 0.5;
    final dx = sx - tx;
    final dy = sy - ty;
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool sofaTvDistanceOk(
    FurnitureItem sofa,
    FurnitureItem tv, {
    double tolerance = sofaTvTolerance,
  }) {
    return (sofaTvCenterDistance(sofa, tv) - sofaTvPreferred).abs() <= tolerance;
  }

  /// Which wall the wardrobe is flush to (left/right/top/bottom).
  static String wardrobeMountWall(FurnitureItem wardrobe, int cols, int rows) {
    final left = wardrobe.gridX;
    final top = wardrobe.gridY;
    final right = cols - (wardrobe.gridX + wardrobe.width);
    final bottom = rows - (wardrobe.gridY + wardrobe.height);
    final best = [
      ('left', left),
      ('right', right),
      ('top', top),
      ('bottom', bottom),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return best.first.$1;
  }

  /// Inward clear strip for wardrobe door swing (AABB in grid space).
  static ({double minX, double minY, double maxX, double maxY}) wardrobeFrontAabb(
    FurnitureItem wardrobe,
    int cols,
    int rows, {
    double depth = wardrobeFrontClearance,
  }) {
    final wall = wardrobeMountWall(wardrobe, cols, rows);
    final x0 = wardrobe.gridX;
    final y0 = wardrobe.gridY;
    final x1 = wardrobe.gridX + wardrobe.width;
    final y1 = wardrobe.gridY + wardrobe.height;
    switch (wall) {
      case 'left':
        return (minX: x1, minY: y0, maxX: x1 + depth, maxY: y1);
      case 'right':
        return (minX: x0 - depth, minY: y0, maxX: x0, maxY: y1);
      case 'top':
        return (minX: x0, minY: y1, maxX: x1, maxY: y1 + depth);
      case 'bottom':
      default:
        return (minX: x0, minY: y0 - depth, maxX: x1, maxY: y0);
    }
  }

  static bool hasWardrobeFrontClearance(
    FurnitureItem wardrobe,
    List<FurnitureItem> others,
    int cols,
    int rows, {
    double depth = wardrobeFrontClearance,
  }) {
    final front = wardrobeFrontAabb(wardrobe, cols, rows, depth: depth);
    for (final o in others) {
      if (o.id == wardrobe.id) continue;
      if (SurfaceMounts.isStructuralMount(o)) continue;
      if (SurfaceMounts.isDeskTopItem(o)) continue;
      if (SurfaceMounts.isCeilingFixture(o)) continue;
      if (_aabbOverlap(
        front.minX,
        front.minY,
        front.maxX,
        front.maxY,
        o.gridX,
        o.gridY,
        o.gridX + o.width,
        o.gridY + o.height,
      )) {
        return false;
      }
    }
    return true;
  }

  static bool _aabbOverlap(
    double ax0,
    double ay0,
    double ax1,
    double ay1,
    double bx0,
    double by0,
    double bx1,
    double by1,
  ) {
    return ax0 < bx1 && ax1 > bx0 && ay0 < by1 && ay1 > by0;
  }
}
