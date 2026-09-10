// lib/services/layout_optimizer_common.dart
// Shared Auto-Rig placement helpers.
//
// Comfort rules live in [ComfortHeuristics] with honest source tiers.
// Placement here applies those heuristics; do not claim ISO/ASHRAE/CPTED
// certification from these poses.
import 'dart:math' as math;

import '../models/room_model.dart';
import '../models/surface_mount.dart';
import '../widgets/furniture_shapes.dart';
import 'comfort_heuristics.dart';
import 'hierarchical_layout.dart';
import 'item_placement_rules.dart';
import 'layout_collision.dart';
import 'layout_orientation.dart';
import 'placement_catalog.dart';

/// Which objective is asking for a work-cluster pose.
enum WorkClusterBias {
  /// Cool the work zone (desk inside AC throw, heat on desk).
  airflow,

  /// Daylight + glare control (desk offset from window axis).
  lighting,

  /// Reach / pull-back / circulation first.
  ergonomics,
}

/// Shared post-pass every domain optimizer runs after x/y placement.
class LayoutOptimizerCommon {
  LayoutOptimizerCommon._();

  /// Chair pull-back used across Auto-Rig (workstation clearance practice).
  static const chairPullback = ComfortHeuristics.chairPullbackMeters;

  /// Minimum clear cells in front of a door (entry circulation practice).
  static const doorApproachDepth = ComfortHeuristics.doorApproachDepth;

  static List<FurnitureItem> applyTargets({
    required List<FurnitureItem> source,
    required Map<String, ({double x, double y})> targets,
    required double cols,
    required double rows,
    required int gridCols,
    required int gridRows,
  }) {
    var next = source.map((item) {
      final pos = targets[item.id];
      if (pos == null) return item.copyWith();
      final maxX = (cols - item.width).clamp(0.0, cols);
      final maxY = (rows - item.height).clamp(0.0, rows);
      return item.copyWith(
        gridX: pos.x.clamp(0.0, maxX),
        gridY: pos.y.clamp(0.0, maxY),
      );
    }).toList(growable: false);

    // Long edge along the side wall before mounting / seating.
    next = _orientWorkDesksAlongSideWalls(next, cols: cols, rows: rows);
    next = mountDeskTopItems(next, gridCols: gridCols, gridRows: gridRows);
    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return next;
  }

  /// Side-wall desks sit with the **long** edge along the wall (depth into the
  /// room is the short edge). A stock 2×1 catalog desk therefore becomes 1×2
  /// on the west/east wall so the chair sits on the long inward face — not the
  /// short stub that used to face into the room.
  static List<FurnitureItem> _orientWorkDesksAlongSideWalls(
    List<FurnitureItem> items, {
    required double cols,
    required double rows,
  }) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked || !_isWorkDesk(f)) continue;
      final preferEast = f.gridX + f.width * 0.5 > cols * 0.5;
      next[i] = _orientDeskAlongSideWall(
        f,
        cols: cols,
        rows: rows,
        preferEast: preferEast,
      );
    }
    return next;
  }

  static FurnitureItem _orientDeskAlongSideWall(
    FurnitureItem desk, {
    required double cols,
    required double rows,
    required bool preferEast,
  }) {
    var w = desk.width;
    var h = desk.height;
    var yaw = desk.yawDegrees;
    // Long axis must run parallel to the side wall (along Y).
    if (w > h + 0.05) {
      final t = w;
      w = h;
      h = t;
      yaw = LayoutOrientation.normalizeYaw(yaw + 90);
    }
    final oriented = desk.copyWith(width: w, height: h, yawDegrees: yaw);
    final maxY = (rows - oriented.height).clamp(0.0, rows);
    final y = oriented.gridY.clamp(0.0, maxY);
    final pinned = _pinDeskToSideWall(
      desk: oriented,
      x: oriented.gridX,
      y: y,
      cols: cols,
      rows: rows,
      preferEast: preferEast,
    );
    return oriented.copyWith(gridX: pinned.x, gridY: pinned.y);
  }

  static FurnitureItem? firstWhere(
    List<FurnitureItem> furniture,
    bool Function(FurnitureItem) test,
  ) {
    for (final f in furniture) {
      if (test(f)) return f;
    }
    return null;
  }

  static FurnitureItem? findDesk(List<FurnitureItem> furniture) {
    // Prefer real desks (id/name) over tables that reuse the desk icon.
    final desks = furniture.where((f) {
      final id = f.id.toLowerCase();
      final name = f.name.toLowerCase();
      return id.contains('desk') || name.contains('desk');
    }).toList();
    if (desks.isNotEmpty) {
      desks.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      return desks.first;
    }
    final hosts = furniture.where(SurfaceMounts.isDeskHost).toList();
    if (hosts.isEmpty) return null;
    hosts.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return hosts.first;
  }

  static bool _isWorkDesk(FurnitureItem f) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();
    return id.contains('desk') || name.contains('desk');
  }

  static FurnitureItem? findChair(List<FurnitureItem> furniture) =>
      firstWhere(furniture, (f) {
        final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
        return f.iconName == 'chair' || hay.contains('chair') || hay.contains('seat');
      });

  /// Primary screen on the desk — chair aligns to this, not the PC.
  static FurnitureItem? findMonitor(List<FurnitureItem> furniture) =>
      firstWhere(furniture, (f) {
        final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
        if (hay.contains('monitor arm') || f.iconName == 'monitorArm') return false;
        return f.iconName == 'monitor' ||
            hay.contains('monitor') ||
            hay.contains('display');
      });

  static FurnitureItem? findDoor(List<FurnitureItem> furniture) =>
      firstWhere(furniture, SurfaceMounts.isDoor);

  static FurnitureItem? findWindow(List<FurnitureItem> furniture) =>
      firstWhere(furniture, SurfaceMounts.isWindow);

  /// Proven desk / chair / desk-top layout for Auto-Rig.
  ///
  /// Writes into [targets] for every matching item id. Returns human reasons.
  static List<String> planWorkCluster({
    required List<FurnitureItem> furniture,
    required Map<String, ({double x, double y})> targets,
    required int gridCols,
    required int gridRows,
    required WorkClusterBias bias,
  }) {
    final reasons = <String>[];
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final desk = findDesk(furniture);
    if (desk == null) return reasons;

    final window = findWindow(furniture);
    final door = findDoor(furniture);
    final deskPose = _deskPose(
      desk: desk,
      window: window,
      door: door,
      cols: cols,
      rows: rows,
      bias: bias,
    );
    targets[desk.id] = deskPose;
    final preferEast = deskPose.x + desk.width * 0.5 > cols * 0.5;
    final seatedDesk = _orientDeskAlongSideWall(
      desk.copyWith(gridX: deskPose.x, gridY: deskPose.y),
      cols: cols,
      rows: rows,
      preferEast: preferEast,
    );
    // Position target matches the oriented footprint (width/height applied in
    // applyTargets / relink via [_orientWorkDesksAlongSideWalls]).
    targets[desk.id] = (x: seatedDesk.gridX, y: seatedDesk.gridY);

    // Any extra work desks also flush to a side wall (never mid-room).
    for (final f in furniture) {
      if (f.locked || f.id == desk.id || !_isWorkDesk(f)) continue;
      final preferEast = deskPose.x < cols * 0.45;
      final y = (deskPose.y + desk.height + chairPullback + 0.4)
          .clamp(0.8, rows - f.height - 0.2);
      targets[f.id] = _pinDeskToSideWall(
        desk: f,
        x: preferEast ? cols : 0,
        y: y,
        cols: cols,
        rows: rows,
        preferEast: preferEast,
      );
    }

    switch (bias) {
      case WorkClusterBias.airflow:
        reasons.add('Desk in the cooled work zone; keep large pieces off AC throw');
      case WorkClusterBias.lighting:
        reasons.add('Desk offset for side daylight — screens at right angles to windows (OSHA)');
      case WorkClusterBias.ergonomics:
        reasons.add('Desk with clear approach and ~${chairPullback.toStringAsFixed(1)} m chair pull-back');
    }

    // Park desk-top gear first so the chair can align to the seated monitor,
    // not the monitor's pre-Auto-Rig floor coordinates.
    var mountedAny = false;
    for (final f in furniture) {
      if (!SurfaceMounts.isDeskTopItem(f) || f.locked) continue;
      targets[f.id] = deskTopTarget(seatedDesk, f);
      mountedAny = true;
    }
    if (mountedAny) {
      reasons.add('Monitor / PC / task lamp on the desk surface — not the floor');
    }

    final chair = findChair(furniture);
    if (chair != null) {
      final monitor = findMonitor(furniture);
      FurnitureItem? alignWith;
      if (monitor != null) {
        final mt = targets[monitor.id];
        alignWith = mt == null
            ? monitor
            : monitor.copyWith(gridX: mt.x, gridY: mt.y);
      }
      targets[chair.id] = chairInFrontOfDesk(
        seatedDesk,
        chair,
        cols: cols,
        rows: rows,
        door: door,
        alignWith: alignWith,
      );
      reasons.add('Centered chair on the desk with ~${chairPullback.toStringAsFixed(1)} m pull-back');
      if (door != null) {
        final prospect = ComfortHeuristics.doorProspectScore(
          chair: chair.copyWith(
            gridX: targets[chair.id]!.x,
            gridY: targets[chair.id]!.y,
          ),
          desk: seatedDesk,
          door: door,
        );
        if (prospect >= 0.65) {
          reasons.add('Seat keeps the entry in view (prospect–refuge preference)');
        } else {
          reasons.add('Nudged seat so the door stays nearer the forward view');
        }
      }
    }

    return reasons;
  }

  /// Chair on the desk's work face (pull-back into the room), aligned with
  /// [alignWith] (usually the monitor) when present so the seat faces the screen.
  ///
  /// Work face prefers the longer desk edge with pull-back room (see
  /// [ItemPlacementRules.deskWorkFace]). After wall desks are oriented
  /// long-along-wall, that is the inward face into the room.
  static ({double x, double y}) chairInFrontOfDesk(
    FurnitureItem desk,
    FurnitureItem chair, {
    required double cols,
    required double rows,
    FurnitureItem? door,
    List<FurnitureItem>? avoid,
    FurnitureItem? alignWith,
  }) {
    final maxX = (cols - chair.width).clamp(0.0, cols);
    final maxY = (rows - chair.height).clamp(0.0, rows);
    final workFace = ItemPlacementRules.deskWorkFace(desk, cols.round(), rows.round());

    // Prefer the monitor center so the chair sits in front of the screen,
    // not merely the desk midpoint (PC often sits on one side).
    final anchor = alignWith ?? desk;
    final ax = anchor.gridX + anchor.width * 0.5;
    final ay = anchor.gridY + anchor.height * 0.5;

    final candidates = <({double x, double y, String face})>[];
    void addFace(String face, double x, double y) {
      candidates.add((x: x, y: y, face: face));
    }

    final south = (
      x: ax - chair.width * 0.5,
      y: desk.gridY + desk.height + chairPullback - chair.height * 0.15,
    );
    final north = (
      x: ax - chair.width * 0.5,
      y: desk.gridY - chairPullback - chair.height * 0.85,
    );
    final east = (
      x: desk.gridX + desk.width + chairPullback - chair.width * 0.15,
      y: ay - chair.height * 0.5,
    );
    final west = (
      x: desk.gridX - chairPullback - chair.width * 0.85,
      y: ay - chair.height * 0.5,
    );

    // Primary work face only — do not fall back to a short-side seat when the
    // long face is available (that put the chair on the stub end of a 2×1 desk).
    switch (workFace) {
      case 'east':
        addFace('east', east.x, east.y);
      case 'west':
        addFace('west', west.x, west.y);
      case 'north':
        addFace('north', north.x, north.y);
      case 'south':
      default:
        addFace('south', south.x, south.y);
    }
    // Only if the primary face is blocked, try the opposite long/short pair.
    switch (workFace) {
      case 'east':
        addFace('west', west.x, west.y);
      case 'west':
        addFace('east', east.x, east.y);
      case 'north':
        addFace('south', south.x, south.y);
      case 'south':
      default:
        addFace('north', north.x, north.y);
    }

    ({double x, double y}) best = (
      x: candidates.first.x.clamp(0.0, maxX),
      y: candidates.first.y.clamp(0.0, maxY),
    );
    var bestScore = -1.0;
    var foundClear = false;

    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c.x < -0.05 || c.y < -0.05 || c.x > maxX + 0.05 || c.y > maxY + 0.05) {
        continue;
      }
      final clamped = (x: c.x.clamp(0.0, maxX), y: c.y.clamp(0.0, maxY));
      final trialChair = chair.copyWith(gridX: clamped.x, gridY: clamped.y);
      if (avoid != null) {
        if (LayoutCollision.itemCollides(trialChair, avoid)) continue;
        var blocksOpening = false;
        for (final other in avoid) {
          final oh = '${other.id} ${other.name} ${other.iconName}'.toLowerCase();
          if (!(oh.contains('door') || oh.contains('window'))) continue;
          if (LayoutCollision.overlaps(trialChair, other)) {
            blocksOpening = true;
            break;
          }
        }
        if (blocksOpening) continue;
      }
      foundClear = true;
      var score = door == null
          ? (i == 0 ? 1.0 : 0.45)
          : ComfortHeuristics.doorProspectScore(
              chair: trialChair,
              desk: desk,
              door: door,
            );
      if (door != null) {
        final approach = _doorApproachRect(door, cols, rows);
        if (LayoutCollision.overlaps(trialChair, approach)) score -= 0.35;
      }
      if (i == 0) {
        score += 0.45;
      } else {
        score -= 0.2;
      }
      // Prefer staying aligned with the screen along the work-face axis.
      if (alignWith != null) {
        final ccx = clamped.x + chair.width * 0.5;
        final ccy = clamped.y + chair.height * 0.5;
        if (workFace == 'south' || workFace == 'north') {
          score += 1.0 - (ccx - ax).abs().clamp(0.0, 1.0);
        } else {
          score += 1.0 - (ccy - ay).abs().clamp(0.0, 1.0);
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = clamped;
      }
    }
    if (foundClear) return best;

    if (avoid == null || !LayoutCollision.itemCollides(chair, avoid)) {
      return (x: chair.gridX.clamp(0.0, maxX), y: chair.gridY.clamp(0.0, maxY));
    }
    return best;
  }

  /// Desk always hugs a wall — never floats mid-room.
  ///
  /// Lighting bias: west or east wall in the daylight band (side light / OSHA).
  /// Airflow / ergonomics: west wall with chair pull-back into the room, clear
  /// of the door approach when possible.
  static ({double x, double y}) _deskPose({
    required FurnitureItem desk,
    required FurnitureItem? window,
    required FurnitureItem? door,
    required double cols,
    required double rows,
    required WorkClusterBias bias,
  }) {
    final maxX = (cols - desk.width).clamp(0.0, cols);
    final maxY = (rows - desk.height).clamp(0.0, rows);
    final wall = ItemPlacementRules.deskWallFlush;

    // Depth along the chosen wall — leave pull-back + aisle into the room.
    var depth = switch (bias) {
      WorkClusterBias.airflow => (rows * 0.22).clamp(0.8, rows - desk.height - chairPullback - 1.2),
      WorkClusterBias.lighting => (window != null ? 1.15 : 1.4)
          .clamp(0.8, rows - desk.height - chairPullback - 1.0),
      WorkClusterBias.ergonomics => (1.35).clamp(0.8, rows - desk.height - chairPullback - 1.2),
    };

    // Default: flush west wall (x = 0).
    var x = wall.clamp(0.0, maxX);
    var y = depth.clamp(0.0, maxY);
    var onEast = false;

    if (bias == WorkClusterBias.lighting && window != null) {
      // Side light: desk on a side wall near the window band, not under the glass.
      final windowCx = window.gridX + window.width * 0.5;
      if (windowCx < cols * 0.5) {
        onEast = true;
        x = (cols - desk.width - wall).clamp(0.0, maxX);
      } else {
        x = wall.clamp(0.0, maxX);
      }
      y = (window.gridY + 1.1).clamp(0.8, maxY);
    }

    // Keep out of the door approach — flip to the opposite side wall if needed,
    // never shove the desk into the room center.
    if (door != null) {
      final approach = _doorApproachRect(door, cols, rows);
      var trial = desk.copyWith(gridX: x, gridY: y);
      if (LayoutCollision.overlaps(trial, approach)) {
        // Slide along the wall in Y first.
        if (door.gridY > rows * 0.5) {
          y = math.min(y, (door.gridY - desk.height - 0.6).clamp(0.5, maxY));
        } else {
          y = math.max(y, (door.gridY + door.height + 0.4).clamp(0.5, maxY));
        }
        trial = desk.copyWith(gridX: x, gridY: y);
        if (LayoutCollision.overlaps(trial, approach)) {
          onEast = !onEast;
          x = onEast
              ? (cols - desk.width - wall).clamp(0.0, maxX)
              : wall.clamp(0.0, maxX);
        }
      }
    }

    // Final wall snap — if anything nudged us inland, pin back to nearest side wall.
    final pinned = _pinDeskToSideWall(
      desk: desk,
      x: x,
      y: y,
      cols: cols,
      rows: rows,
      preferEast: onEast,
    );
    return (x: pinned.x.clamp(0.0, maxX), y: pinned.y.clamp(0.0, maxY));
  }

  static ({double x, double y}) _pinDeskToSideWall({
    required FurnitureItem desk,
    required double x,
    required double y,
    required double cols,
    required double rows,
    bool preferEast = false,
  }) {
    final flush = ItemPlacementRules.deskWallFlush;
    final maxX = (cols - desk.width).clamp(0.0, cols);
    final maxY = (rows - desk.height).clamp(0.0, rows);
    final left = x;
    final right = cols - (x + desk.width);
    // Always pin flush to a vertical wall so the chair has a clear inward face.
    final useEast = preferEast || (right + 0.05 < left);
    final pinnedX = useEast
        ? (cols - desk.width - flush).clamp(0.0, maxX)
        : flush.clamp(0.0, maxX);
    return (x: pinnedX, y: y.clamp(0.0, maxY));
  }

  static FurnitureItem _doorApproachRect(FurnitureItem door, double cols, double rows) {
    // Inflate the door footprint inward into the room for aisle clearance.
    final mount = SurfaceMounts.of(
      door,
      gridCols: cols.round().clamp(1, 64),
      gridRows: rows.round().clamp(1, 64),
    );
    final span = mount.span;
    if (span != null) {
      final inwardX = span.inwardX.abs() > 0.01 ? span.inwardX : 0.0;
      final inwardZ = span.inwardZ.abs() > 0.01 ? span.inwardZ : 0.0;
      final x0 = math.min(span.x0, span.x0 + inwardX * doorApproachDepth);
      final z0 = math.min(span.z0, span.z0 + inwardZ * doorApproachDepth);
      final x1 = math.max(span.x1, span.x1 + inwardX * doorApproachDepth);
      final z1 = math.max(span.z1, span.z1 + inwardZ * doorApproachDepth);
      return door.copyWith(
        gridX: x0.clamp(0.0, cols),
        gridY: z0.clamp(0.0, rows),
        width: (x1 - x0).clamp(0.5, cols),
        height: (z1 - z0).clamp(0.5, rows),
      );
    }
    return door.copyWith(
      width: door.width + doorApproachDepth,
      height: door.height + doorApproachDepth,
    );
  }

  /// Prefer desk surface for monitor / PC / task lamp whenever a desk exists.
  ///
  /// Order of intent (do not reverse):
  /// 1) work face = long desk edge with pull-back (after wall-desk orientation)
  /// 2) monitor on the wall/back edge, facing that work face
  /// 3) PC beside the monitor along the wall — never between screen and chair
  /// 4) chair is seated separately on the work face in front of the monitor
  static List<FurnitureItem> mountDeskTopItems(
    List<FurnitureItem> furniture, {
    int? gridCols,
    int? gridRows,
  }) {
    final hosts = furniture.where(SurfaceMounts.isDeskHost).toList();
    if (hosts.isEmpty) return furniture;

    // Work desk first — never treat a coffee table as the primary PC host.
    final primary = findDesk(furniture) ??
        (hosts
              ..sort(
                (a, b) => (b.width * b.height).compareTo(a.width * a.height),
              ))
            .first;

    final next = furniture.map((f) => f.copyWith()).toList();
    final desktopIdx = <int>[];
    for (var i = 0; i < next.length; i++) {
      final item = next[i];
      if (item.locked) continue;
      if (!SurfaceMounts.isDeskTopItem(item)) continue;
      desktopIdx.add(i);
    }
    if (desktopIdx.isEmpty) return furniture;

    desktopIdx.sort((a, b) => _deskItemRank(next[a]).compareTo(_deskItemRank(next[b])));

    final placedOnHost = <String, List<FurnitureItem>>{};
    for (final i in desktopIdx) {
      var item = next[i];
      final host = _hostForDeskTopItem(
        item,
        next,
        primary,
        placedOnHost: placedOnHost,
      );
      final hay = ItemPlacementRules.hay(item);
      // Fit lounge stackables on a table top (leave room for a plant beside the TV).
      if (ItemPlacementRules.isTv(item)) {
        final depth = math.min(item.height, 0.45);
        var width = item.width;
        if (SurfaceMounts.isTableHost(host) && width > host.width - 0.5) {
          width = math.max(1.0, host.width - 0.55);
        }
        item = item.copyWith(width: width, height: depth);
        next[i] = item;
      } else if (hay.contains('plant')) {
        item = item.copyWith(
          width: math.min(item.width, 0.5),
          height: math.min(item.height, 0.5),
        );
        next[i] = item;
      } else if ((hay.contains('lamp') || item.iconName == 'lamp') &&
          !hay.contains('floor')) {
        item = item.copyWith(
          width: math.min(item.width, 0.4),
          height: math.min(item.height, 0.4),
        );
        next[i] = item;
      }
      final others = placedOnHost.putIfAbsent(host.id, () => <FurnitureItem>[]);
      final cols = gridCols ??
          math.max(8, (host.gridX + host.width + 4).ceil());
      final rows = gridRows ??
          math.max(8, (host.gridY + host.height + 4).ceil());
      final workFace = ItemPlacementRules.deskWorkFace(host, cols, rows);
      final slot = _deskSlot(
        host: host,
        item: item,
        alreadyOnHost: others,
        rank: _deskItemRank(item),
        workFace: workFace,
        room: next,
        gridCols: cols,
        gridRows: rows,
      );
      final seated = item.copyWith(gridX: slot.$1, gridY: slot.$2);
      next[i] = seated;
      others.add(seated);
    }
    return separateDeskTopOverlaps(next);
  }

  /// True for workstation gear that must share one work desk (never a lounge table).
  static bool _isWorkClusterDeskItem(FurnitureItem item) {
    final hay = ItemPlacementRules.hay(item);
    if (ItemPlacementRules.isTv(item) || hay.contains('plant')) return false;
    if (hay.contains('monitor') ||
        hay.contains('display') ||
        hay.contains('pc') ||
        hay.contains('tower') ||
        hay.contains('computer') ||
        hay.contains('cable') ||
        hay.contains('light bar') ||
        item.iconName == 'monitor' ||
        item.iconName == 'monitorArm' ||
        item.iconName == 'pc' ||
        item.iconName == 'lightBar' ||
        item.iconName == 'cableTray') {
      return true;
    }
    if ((hay.contains('lamp') || item.iconName == 'lamp') && !hay.contains('floor')) {
      return true;
    }
    return false;
  }

  /// TV / plant prefer a lounge table; monitor + PC + lamp stay on one work desk.
  static FurnitureItem _hostForDeskTopItem(
    FurnitureItem item,
    List<FurnitureItem> room,
    FurnitureItem primary, {
    Map<String, List<FurnitureItem>>? placedOnHost,
  }) {
    final hay = ItemPlacementRules.hay(item);
    final wantsTable =
        ItemPlacementRules.isTv(item) || hay.contains('plant');

    if (_isWorkClusterDeskItem(item) || !wantsTable) {
      final desk = findDesk(room) ?? primary;
      // Join the work surface that already holds the monitor / PC so the
      // cluster never splits across desk + lounge table after a blend.
      if (placedOnHost != null && placedOnHost.isNotEmpty) {
        for (final entry in placedOnHost.entries) {
          final hasPeer = entry.value.any(_isWorkClusterDeskItem);
          if (!hasPeer) continue;
          for (final f in room) {
            if (f.id != entry.key) continue;
            if (SurfaceMounts.isTableHost(f)) break;
            return f;
          }
        }
      }
      // Ignore accidental overlap with a lounge table from pose blending.
      final under = SurfaceMounts.hostUnder(item, room);
      if (under != null &&
          !SurfaceMounts.isTableHost(under) &&
          _isWorkDesk(under)) {
        return under;
      }
      return desk;
    }

    final under = SurfaceMounts.hostUnder(item, room);
    if (under != null && SurfaceMounts.isTableHost(under)) return under;
    final tables = room.where(SurfaceMounts.isTableHost).toList()
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    if (tables.isNotEmpty) {
      if (tables.length == 1) return tables.first;
      final desk = findDesk(room);
      if (desk == null) return tables.first;
      tables.sort((a, b) {
        final da = (a.gridX - desk.gridX).abs() + (a.gridY - desk.gridY).abs();
        final db = (b.gridX - desk.gridX).abs() + (b.gridY - desk.gridY).abs();
        return db.compareTo(da);
      });
      return tables.first;
    }
    return primary;
  }

  /// Target pose on [host] for a desk-top item (used by domain optimizers).
  static ({double x, double y}) deskTopTarget(FurnitureItem host, FurnitureItem item) {
    final cols = math.max(8, (host.gridX + host.width + 4).ceil());
    final rows = math.max(8, (host.gridY + host.height + 4).ceil());
    final slot = _deskSlot(
      host: host,
      item: item,
      alreadyOnHost: const [],
      rank: _deskItemRank(item),
      workFace: ItemPlacementRules.deskWorkFace(host, cols, rows),
      gridCols: cols,
      gridRows: rows,
    );
    return (x: slot.$1, y: slot.$2);
  }

  static int _deskItemRank(FurnitureItem f) {
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    if (hay.contains('monitor') ||
        hay.contains('screen') ||
        hay.contains('display') ||
        hay.contains('monitorarm') ||
        f.iconName == 'monitorArm' ||
        ItemPlacementRules.isTv(f)) {
      return 0;
    }
    if (hay.contains('cable')) return 2;
    if (hay.contains('pc') || hay.contains('tower') || hay.contains('computer')) {
      return 4;
    }
    if (hay.contains('plant')) return 5;
    return 1; // lamp / light bar
  }

  /// Desk-top slots relative to [workFace] (chair side):
  /// - Monitor: wall / back edge, looking toward the work face
  /// - PC: beside monitor along the wall — never toward the chair
  /// - Lamp: other side of monitor along the wall
  ///
  /// Floor fallbacks stay **inside the room** (never `x < 0` through a side wall).
  static (double, double) _deskSlot({
    required FurnitureItem host,
    required FurnitureItem item,
    required List<FurnitureItem> alreadyOnHost,
    required int rank,
    required String workFace,
    List<FurnitureItem> room = const [],
    int gridCols = 8,
    int gridRows = 8,
  }) {
    final roomMaxX = math.max(0.0, gridCols - item.width);
    final roomMaxY = math.max(0.0, gridRows - item.height);
    (double, double) clampRoom(double x, double y) => (
          x.clamp(0.0, roomMaxX),
          y.clamp(0.0, roomMaxY),
        );

    final maxX = host.gridX + host.width - item.width;
    final maxY = host.gridY + host.height - item.height;
    final loX = host.gridX;
    final loY = host.gridY;
    final hiX = math.max(loX, maxX);
    final hiY = math.max(loY, maxY);
    final fitsOnDesk = item.width <= host.width + 0.05 && item.height <= host.height + 0.05;

    bool blocksOpening(FurnitureItem candidate) {
      for (final other in room) {
        if (other.id == candidate.id || other.id == host.id) continue;
        final oh = '${other.id} ${other.name} ${other.iconName}'.toLowerCase();
        if (!(oh.contains('door') || oh.contains('window'))) continue;
        if (LayoutCollision.overlaps(candidate, other)) return true;
      }
      return false;
    }

    // Wall / back edge of the desk (opposite the chair).
    late final double backX;
    late final double backY;
    switch (workFace) {
      case 'east': // chair east → back is west wall edge
        backX = loX;
        backY = loY + (hiY - loY) * 0.5;
      case 'west':
        backX = hiX;
        backY = loY + (hiY - loY) * 0.5;
      case 'north':
        backX = loX + (hiX - loX) * 0.5;
        backY = hiY;
      case 'south':
      default:
        backX = loX + (hiX - loX) * 0.5;
        backY = loY;
    }

    late double preferX;
    late double preferY;
    switch (rank) {
      case 0: // monitor — centered on the back edge
        preferX = host.width <= 2.01 && (workFace == 'south' || workFace == 'north')
            ? loX
            : backX.clamp(loX, hiX);
        preferY = backY.clamp(loY, hiY);
        if (workFace == 'east' || workFace == 'west') {
          preferX = backX.clamp(loX, hiX);
          preferY = (loY + (hiY - loY) * 0.35).clamp(loY, hiY);
        }
      case 4: // PC — wall edge, beside monitor along the wall (never toward chair)
        FurnitureItem? monitor;
        for (final o in alreadyOnHost) {
          final oh = '${o.id} ${o.name} ${o.iconName}'.toLowerCase();
          if (oh.contains('monitor') || oh.contains('display') || o.iconName == 'monitor') {
            monitor = o;
            break;
          }
        }
        final pcsOnHost = alreadyOnHost.where((o) => _deskItemRank(o) == 4).length;
        if (pcsOnHost >= 1 || !fitsOnDesk) {
          // Extra / oversized towers: floor flush to the same wall, still indoors.
          preferX = switch (workFace) {
            'east' => 0.0,
            'west' => roomMaxX,
            _ => host.gridX.clamp(0.0, roomMaxX),
          };
          preferY = host.gridY.clamp(0.0, roomMaxY);
          break;
        }
        if (monitor != null) {
          final alongWall = _besideAlongWall(
            monitor: monitor,
            item: item,
            workFace: workFace,
            loX: loX,
            loY: loY,
            hiX: hiX,
            hiY: hiY,
          );
          preferX = alongWall.$1;
          preferY = alongWall.$2;
          switch (workFace) {
            case 'east':
              preferX = loX;
            case 'west':
              preferX = hiX;
            case 'north':
              preferY = hiY;
            case 'south':
            default:
              preferY = loY;
          }
        } else {
          preferX = backX.clamp(loX, hiX);
          preferY = backY.clamp(loY, hiY);
        }
      default: // lamp — other side of monitor along the wall
        FurnitureItem? monitor;
        for (final o in alreadyOnHost) {
          final oh = '${o.id} ${o.name} ${o.iconName}'.toLowerCase();
          if (oh.contains('monitor') || o.iconName == 'monitor') {
            monitor = o;
            break;
          }
        }
        if (monitor != null) {
          final alongWall = _besideAlongWall(
            monitor: monitor,
            item: item,
            workFace: workFace,
            loX: loX,
            loY: loY,
            hiX: hiX,
            hiY: hiY,
            preferOpposite: true,
          );
          preferX = alongWall.$1;
          preferY = alongWall.$2;
        } else {
          preferX = hiX;
          preferY = backY.clamp(loY, hiY);
        }
    }

    // On-desk search first when the footprint fits.
    if (fitsOnDesk) {
      preferX = preferX.clamp(loX, hiX);
      preferY = preferY.clamp(loY, hiY);

      final candidates = <(double, double)>[
        (preferX, preferY),
        (loX, preferY),
        (hiX, preferY),
        (preferX, hiY),
        (preferX, loY),
        (loX, loY),
        (hiX, loY),
        (loX, hiY),
        (hiX, hiY),
      ];
      for (var step = 0; step <= 8; step++) {
        final t = step * 0.25;
        if (workFace == 'south' || workFace == 'north') {
          candidates.addAll([
            ((preferX + t).clamp(loX, hiX), preferY),
            ((preferX - t).clamp(loX, hiX), preferY),
          ]);
        } else {
          candidates.addAll([
            (preferX, (preferY + t).clamp(loY, hiY)),
            (preferX, (preferY - t).clamp(loY, hiY)),
          ]);
        }
      }

      for (final (x, y) in candidates) {
        final candidate = item.copyWith(gridX: x, gridY: y);
        if (blocksOpening(candidate)) continue;
        if (rank == 4 && _onWorkFaceSideOfDesk(candidate, host, workFace)) {
          continue;
        }
        final clash = alreadyOnHost.any(
          (o) =>
              LayoutCollision.overlaps(candidate, o) &&
              SurfaceMounts.deskTopFootprintsConflict(candidate, o),
        );
        if (!clash) return clampRoom(x, y);
      }

      // Walk the back edge on the desk before leaving the surface.
      for (var t = 0.0; t <= 1.001; t += 0.2) {
        final (x, y) = switch (workFace) {
          'east' => (loX, (loY + (hiY - loY) * t).clamp(loY, hiY)),
          'west' => (hiX, (loY + (hiY - loY) * t).clamp(loY, hiY)),
          'north' => ((loX + (hiX - loX) * t).clamp(loX, hiX), hiY),
          _ => ((loX + (hiX - loX) * t).clamp(loX, hiX), loY),
        };
        final candidate = item.copyWith(gridX: x, gridY: y);
        if (blocksOpening(candidate)) continue;
        if (rank == 4 && _onWorkFaceSideOfDesk(candidate, host, workFace)) {
          continue;
        }
        final clash = alreadyOnHost.any(
          (o) =>
              LayoutCollision.overlaps(candidate, o) &&
              SurfaceMounts.deskTopFootprintsConflict(candidate, o),
        );
        if (!clash) return clampRoom(x, y);
      }
    }

    // Floor beside desk — flush to the same wall, always inside the room.
    // Never use host.gridX - item.width (that punched through the west wall).
    final alongWall = <(double, double)>[];
    switch (workFace) {
      case 'east':
        alongWall.addAll([
          (0.0, (host.gridY - item.height).clamp(0.0, roomMaxY)),
          (0.0, (host.gridY + host.height).clamp(0.0, roomMaxY)),
          (0.0, host.gridY.clamp(0.0, roomMaxY)),
          if (fitsOnDesk) (loX, loY),
          if (fitsOnDesk) (loX, hiY),
        ]);
      case 'west':
        alongWall.addAll([
          (roomMaxX, (host.gridY - item.height).clamp(0.0, roomMaxY)),
          (roomMaxX, (host.gridY + host.height).clamp(0.0, roomMaxY)),
          (roomMaxX, host.gridY.clamp(0.0, roomMaxY)),
          if (fitsOnDesk) (hiX, loY),
          if (fitsOnDesk) (hiX, hiY),
        ]);
      case 'north':
        alongWall.addAll([
          (host.gridX.clamp(0.0, roomMaxX), roomMaxY),
          ((host.gridX + host.width - item.width).clamp(0.0, roomMaxX), roomMaxY),
          if (fitsOnDesk) (loX, hiY),
          if (fitsOnDesk) (hiX, hiY),
        ]);
      case 'south':
      default:
        alongWall.addAll([
          (host.gridX.clamp(0.0, roomMaxX), 0.0),
          ((host.gridX + host.width - item.width).clamp(0.0, roomMaxX), 0.0),
          if (fitsOnDesk) (loX, loY),
          if (fitsOnDesk) (hiX, loY),
        ]);
    }
    for (final (x0, y0) in alongWall) {
      final (x, y) = clampRoom(x0, y0);
      final candidate = item.copyWith(gridX: x, gridY: y);
      if (blocksOpening(candidate)) continue;
      final onDesk = x >= host.gridX - 0.01 &&
          y >= host.gridY - 0.01 &&
          x + item.width <= host.gridX + host.width + 0.01 &&
          y + item.height <= host.gridY + host.height + 0.01;
      if (rank == 4 && onDesk && _onWorkFaceSideOfDesk(candidate, host, workFace)) {
        continue;
      }
      final clash = alreadyOnHost.any(
        (o) =>
            LayoutCollision.overlaps(candidate, o) &&
            SurfaceMounts.deskTopFootprintsConflict(candidate, o),
      );
      if (!clash) return (x, y);
    }

    // Last resort: back corner of the desk if it fits, else wall-flush indoors.
    if (fitsOnDesk) {
      return clampRoom(backX.clamp(loX, hiX), backY.clamp(loY, hiY));
    }
    return clampRoom(preferX, preferY);
  }

  /// Offset beside [monitor] along the wall axis (perpendicular to [workFace]).
  static (double, double) _besideAlongWall({
    required FurnitureItem monitor,
    required FurnitureItem item,
    required String workFace,
    required double loX,
    required double loY,
    required double hiX,
    required double hiY,
    bool preferOpposite = false,
  }) {
    if (workFace == 'south' || workFace == 'north') {
      // Wall runs along X — sit left or right of the monitor, same back Y.
      final left = monitor.gridX - item.width;
      final right = monitor.gridX + monitor.width;
      final y = monitor.gridY.clamp(loY, hiY);
      if (!preferOpposite) {
        if (left >= loX - 0.01) return (left.clamp(loX, hiX), y);
        return (right.clamp(loX, hiX), y);
      }
      if (right <= hiX + 0.01) return (right.clamp(loX, hiX), y);
      return (left.clamp(loX, hiX), y);
    }
    // Wall runs along Y — sit north/south of the monitor, same back X.
    final up = monitor.gridY - item.height;
    final down = monitor.gridY + monitor.height;
    final x = monitor.gridX.clamp(loX, hiX);
    if (!preferOpposite) {
      if (up >= loY - 0.01) return (x, up.clamp(loY, hiY));
      return (x, down.clamp(loY, hiY));
    }
    if (down <= hiY + 0.01) return (x, down.clamp(loY, hiY));
    return (x, up.clamp(loY, hiY));
  }

  /// True when [item] sits on the chair-side half of the desk (blocks the screen).
  static bool _onWorkFaceSideOfDesk(
    FurnitureItem item,
    FurnitureItem host,
    String workFace,
  ) {
    final cx = item.gridX + item.width * 0.5;
    final cy = item.gridY + item.height * 0.5;
    final midX = host.gridX + host.width * 0.5;
    final midY = host.gridY + host.height * 0.5;
    switch (workFace) {
      case 'east':
        return cx > midX + 0.05;
      case 'west':
        return cx < midX - 0.05;
      case 'north':
        return cy < midY - 0.05;
      case 'south':
      default:
        return cy > midY + 0.05;
    }
  }

  /// Push overlapping desk-top items apart on their shared host.
  static List<FurnitureItem> separateDeskTopOverlaps(List<FurnitureItem> furniture) {
    final mutable = furniture.map((f) => f.copyWith()).toList();
    for (var pass = 0; pass < 24; pass++) {
      var moved = false;
      for (var i = 0; i < mutable.length; i++) {
        final a = mutable[i];
        if (!SurfaceMounts.isDeskTopItem(a)) continue;
        final host = SurfaceMounts.hostUnder(a, mutable);
        if (host == null) continue;
        for (var j = i + 1; j < mutable.length; j++) {
          final b = mutable[j];
          if (!SurfaceMounts.isDeskTopItem(b)) continue;
          if (!LayoutCollision.overlaps(a, b)) continue;
          if (!SurfaceMounts.deskTopFootprintsConflict(a, b)) continue;
          final hostB = SurfaceMounts.hostUnder(b, mutable);
          if (hostB?.id != host.id) continue;

          final moverIdx = _deskItemRank(mutable[j]) >= _deskItemRank(mutable[i]) ? j : i;
          final mover = mutable[moverIdx];
          final others = [
            for (var k = 0; k < mutable.length; k++)
              if (k != moverIdx &&
                  SurfaceMounts.isDeskTopItem(mutable[k]) &&
                  SurfaceMounts.hostUnder(mutable[k], mutable)?.id == host.id)
                mutable[k],
          ];
          final cols = math.max(8, (host.gridX + host.width + 4).ceil());
          final rows = math.max(8, (host.gridY + host.height + 4).ceil());
          final slot = _deskSlot(
            host: host,
            item: mover,
            alreadyOnHost: others,
            rank: _deskItemRank(mover),
            workFace: ItemPlacementRules.deskWorkFace(host, cols, rows),
            room: mutable,
            gridCols: cols,
            gridRows: rows,
          );
          final next = mover.copyWith(gridX: slot.$1, gridY: slot.$2);
          if ((next.gridX - mover.gridX).abs() > 0.01 ||
              (next.gridY - mover.gridY).abs() > 0.01) {
            mutable[moverIdx] = next;
            moved = true;
          } else if (host.width >= mover.width * 2) {
            // Last resort: park on the opposite side of the host.
            final flipX = mover.gridX <= host.gridX + host.width * 0.5
                ? host.gridX + host.width - mover.width
                : host.gridX;
            mutable[moverIdx] = mover.copyWith(gridX: flipX.clamp(host.gridX, host.gridX + host.width - mover.width));
            moved = true;
          }
        }
      }
      if (!moved) break;
    }
    return mutable;
  }

  /// Soft perimeter targets for large non-work pieces (bed, storage, sofa).
  static void planPerimeterStorage({
    required List<FurnitureItem> furniture,
    required Map<String, ({double x, double y})> targets,
    required int gridCols,
    required int gridRows,
    required List<String> reasons,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final desk = findDesk(furniture);
    final door = findDoor(furniture);

    for (final f in furniture) {
      if (f.locked) continue;
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      if (hay.contains('bed')) {
        // Hierarchical: bed chooses from wall/corner candidates only (headboard edge).
        // Soft desk clearance + privacy score pick among legal wall poses — never float.
        final deskSeated = desk == null
            ? null
            : desk.copyWith(
                gridX: targets[desk.id]?.x ?? desk.gridX,
                gridY: targets[desk.id]?.y ?? desk.gridY,
              );
        final candidates = <({double x, double y})>[
          (x: 0.0, y: (rows - f.height).clamp(0.0, rows - f.height)),
          (x: (cols - f.width).clamp(0.0, cols - f.width), y: (rows - f.height).clamp(0.0, rows - f.height)),
          (x: 0.0, y: 0.0),
          (x: (cols - f.width).clamp(0.0, cols - f.width), y: 0.0),
          (x: ((cols - f.width) * 0.5).clamp(0.0, cols - f.width), y: (rows - f.height).clamp(0.0, rows - f.height)),
          (x: 0.0, y: ((rows - f.height) * 0.5).clamp(0.0, rows - f.height)),
          (x: (cols - f.width).clamp(0.0, cols - f.width), y: ((rows - f.height) * 0.5).clamp(0.0, rows - f.height)),
        ];
        var best = candidates.first;
        var bestScore = -1.0;
        for (final cand in candidates) {
          final trial = f.copyWith(gridX: cand.x, gridY: cand.y);
          var score = HierarchicalLayout.wallTouchCount(
                trial,
                gridCols,
                gridRows,
              ) *
              2.0;
          score += cand.y * 0.1; // prefer far (south) sleep wall
          if (deskSeated != null) {
            if (!ItemPlacementRules.hasClearGap(
              trial,
              deskSeated,
              ItemPlacementRules.deskBedClearance,
            )) {
              continue;
            }
            score += 1.5;
          }
          if (door != null) {
            score += ComfortHeuristics.bedPrivacyFromDoor(
              bed: trial,
              door: door,
              gridCols: gridCols,
              gridRows: gridRows,
            );
          }
          if (score > bestScore) {
            bestScore = score;
            best = cand;
          }
        }
        targets[f.id] = (x: best.x, y: best.y);
        if (!reasons.any((r) => r.toLowerCase().contains('bed'))) {
          reasons.add(
            bestScore >= 0
                ? 'Bed headboard/edge on a wall (corner preferred) — sleep zone'
                : 'Bed on a wall edge clear of the work zone',
          );
        }
      } else if (hay.contains('shelf') || hay.contains('book') || hay.contains('wardrobe')) {
        // Tall storage flush to a wall/corner — never mid-room (interior guides).
        final onRight = door == null || door.gridX < cols * 0.5;
        var sx = onRight ? (cols - f.width).clamp(0.0, cols - f.width) : 0.0;
        var sy = (rows - f.height - 0.15).clamp(0.0, rows - f.height);
        // Prefer a free corner if the default is already claimed.
        if (desk != null) {
          final deskPose = targets[desk.id];
          if (deskPose != null) {
            final trial = f.copyWith(gridX: sx, gridY: sy);
            final seated = desk.copyWith(gridX: deskPose.x, gridY: deskPose.y);
            if (!ItemPlacementRules.hasClearGap(trial, seated, 0.85)) {
              sx = onRight ? 0.0 : (cols - f.width).clamp(0.0, cols - f.width);
              sy = (rows - f.height - 0.15).clamp(0.0, rows - f.height);
            }
          }
        }
        targets[f.id] = (x: sx, y: sy);
        if (!reasons.any((r) => r.contains('storage'))) {
          reasons.add('Tall storage flush to a wall/corner — out of throw / daylight lanes');
        }
      } else if (hay.contains('sofa') || hay.contains('couch')) {
        // Prefer back against a wall (sorting.md) — west wall lounge default.
        targets[f.id] = (
          x: 0.0,
          y: (rows * 0.38).clamp(1.5, rows - f.height - 0.5),
        );
      } else if (hay.contains('plant')) {
        targets[f.id] = (x: (cols - f.width).clamp(0.0, cols - f.width), y: 2.0);
      } else if (hay.contains('tv') || hay.contains('television')) {
        // Placeholder — paired with sofa below when both present.
        targets[f.id] = (
          x: (cols - f.width - 0.15).clamp(0.0, cols - f.width),
          y: (rows * 0.35).clamp(1.2, rows - f.height - 0.5),
        );
      } else if (hay.contains('heater')) {
        targets[f.id] = (
          x: (cols * 0.55).clamp(0.0, cols - f.width),
          y: (rows - f.height - 0.4).clamp(0.0, rows - f.height),
        );
      } else if (hay.contains('floorlamp') || hay.contains('floor_lamp') || hay.contains('floor lamp')) {
        targets[f.id] = (
          x: 0.2.clamp(0.0, cols - f.width),
          y: (rows * 0.55).clamp(1.0, rows - f.height),
        );
      } else if (hay.contains('purifier') || hay.contains('mat')) {
        // Near the work zone but on the floor — south of desk if present.
        final dx = desk != null ? (targets[desk.id]?.x ?? desk.gridX) : 1.0;
        final dy = desk != null
            ? (targets[desk.id]?.y ?? desk.gridY) + desk.height + 0.3
            : rows * 0.45;
        targets[f.id] = (
          x: dx.clamp(0.0, cols - f.width),
          y: dy.clamp(0.0, rows - f.height),
        );
      } else if (hay.contains('blind') || f.iconName == 'smartBlinds') {
        // On the window wall for glare control (OSHA: blinds + furniture).
        final window = findWindow(furniture);
        if (window != null) {
          targets[f.id] = (
            x: window.gridX.clamp(0.0, cols - f.width),
            y: 0.05.clamp(0.0, rows - f.height),
          );
        } else {
          targets[f.id] = (x: (cols * 0.35).clamp(0.0, cols - f.width), y: 0.05);
        }
        if (!reasons.any((r) => r.contains('blind'))) {
          reasons.add('Blinds on the window wall to cut glare');
        }
      } else if (hay.contains('portable') && (hay.contains('ac') || f.iconName == 'ac')) {
        // Floor cooler mid-room, clear of wall vents.
        targets[f.id] = (
          x: (cols * 0.35).clamp(0.0, cols - f.width),
          y: (rows * 0.45).clamp(1.0, rows - f.height),
        );
        if (!reasons.any((r) => r.contains('Portable'))) {
          reasons.add('Portable AC on the floor in open volume — not jammed on a wall');
        }
      } else if (hay.contains('ceiling') || f.iconName == 'ceilingLight') {
        targets[f.id] = (
          x: (cols * 0.5 - f.width * 0.5).clamp(0.0, cols - f.width),
          y: (rows * 0.45 - f.height * 0.5).clamp(0.0, rows - f.height),
        );
      } else if (hay.contains('table') && !hay.contains('cable') && desk != null && f.id != desk.id) {
        // Secondary table: lounge / side table, not competing with the work desk.
        targets[f.id] = (
          x: 0.2.clamp(0.0, cols - f.width),
          y: (rows * 0.42).clamp(1.5, rows - f.height),
        );
      }
    }

    _pairSofaAndTv(furniture, targets, cols, rows, reasons);
    _separateOverlappingTargets(furniture, targets, cols, rows);
  }

  /// Place sofa + TV facing each other near [ItemPlacementRules.sofaTvPreferred].
  /// When a lounge table exists, park it under the TV so the screen sits on top.
  static void _pairSofaAndTv(
    List<FurnitureItem> furniture,
    Map<String, ({double x, double y})> targets,
    double cols,
    double rows,
    List<String> reasons,
  ) {
    FurnitureItem? sofa;
    FurnitureItem? tv;
    FurnitureItem? table;
    for (final f in furniture) {
      if (f.locked) continue;
      if (ItemPlacementRules.isSofa(f)) sofa ??= f;
      if (ItemPlacementRules.isTv(f)) tv ??= f;
      if (SurfaceMounts.isTableHost(f)) table ??= f;
    }
    if (sofa == null && tv == null) return;

    final bandY = (rows * 0.38).clamp(1.2, rows - 2.0);
    if (sofa != null && tv == null) {
      targets[sofa.id] = (
        x: 0.0,
        y: bandY.clamp(0.0, rows - sofa.height),
      );
      if (!reasons.any((r) => r.contains('Sofa'))) {
        reasons.add('Sofa on the west wall lounge zone — separate from the bed');
      }
      return;
    }
    if (tv != null && sofa == null) {
      final tvDepth = tv.height > 0.55 ? 0.45 : tv.height;
      final tvX = (cols - tv.width - 0.15).clamp(0.0, cols - tv.width);
      final tvY = bandY.clamp(0.0, rows - tvDepth);
      targets[tv.id] = (x: tvX, y: tvY);
      if (table != null) {
        final hostX = tvX.clamp(0.0, cols - table.width);
        final hostY = tvY.clamp(0.0, rows - table.height);
        targets[table.id] = (x: hostX, y: hostY);
        targets[tv.id] = (
          x: (hostX + (table.width - tv.width) * 0.5)
              .clamp(hostX, hostX + table.width - tv.width),
          y: (hostY + (table.height - tvDepth) * 0.5)
              .clamp(hostY, hostY + table.height - tvDepth),
        );
      }
      if (!reasons.any((r) => r.contains('TV'))) {
        reasons.add(table != null
            ? 'TV on the lounge table facing the room'
            : 'TV on a clear wall for lounge viewing');
      }
      return;
    }

    final s = sofa!;
    final t = tv!;
    final preferred = ItemPlacementRules.sofaTvPreferred;
    final tvDepth = t.height > 0.55 ? 0.45 : t.height;
    var sofaX = 0.0;
    var sofaY = bandY.clamp(0.0, rows - s.height);
    var sofaCx = sofaX + s.width * 0.5;
    var tvCx = sofaCx + preferred;
    var tvX = (tvCx - t.width * 0.5).clamp(0.0, cols - t.width);
    var tvY = sofaY.clamp(0.0, rows - tvDepth);

    // Room too narrow for preferred span — pin TV to east wall and pull sofa in.
    if (tvX + t.width > cols - 0.05 || (tvX + t.width * 0.5) - sofaCx < preferred - 0.35) {
      tvX = (cols - t.width - 0.1).clamp(0.0, cols - t.width);
      final actualTvCx = tvX + t.width * 0.5;
      final desiredSofaCx = (actualTvCx - preferred).clamp(s.width * 0.5, cols - s.width * 0.5);
      sofaX = (desiredSofaCx - s.width * 0.5).clamp(0.0, cols - s.width);
      sofaCx = sofaX + s.width * 0.5;
    }

    targets[s.id] = (x: sofaX, y: sofaY);
    targets[t.id] = (x: tvX, y: tvY);
    if (table != null) {
      final hostX = tvX.clamp(0.0, cols - table.width);
      final hostY = tvY.clamp(0.0, rows - table.height);
      targets[table.id] = (x: hostX, y: hostY);
      targets[t.id] = (
        x: (hostX + (table.width - t.width) * 0.5)
            .clamp(hostX, hostX + table.width - t.width),
        y: (hostY + (table.height - tvDepth) * 0.5)
            .clamp(hostY, hostY + table.height - tvDepth),
      );
    }
    if (!reasons.any((r) => r.contains('Sofa↔TV') || r.contains('Sofa-TV'))) {
      reasons.add(table != null
          ? 'Sofa↔TV on lounge table ~${preferred.toStringAsFixed(1)} cell viewing distance'
          : 'Sofa↔TV ~${preferred.toStringAsFixed(1)} cell viewing distance (lounge guides)');
    }
  }

  static bool _isLargePerimeterPiece(FurnitureItem f) {
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    return hay.contains('bed') || hay.contains('sofa') || hay.contains('couch');
  }

  /// Nudge bed / sofa targets apart when both land on the back wall.
  static void _separateOverlappingTargets(
    List<FurnitureItem> furniture,
    Map<String, ({double x, double y})> targets,
    double cols,
    double rows,
  ) {
    final pieces = furniture
        .where((f) => !f.locked && _isLargePerimeterPiece(f) && targets.containsKey(f.id))
        .toList(growable: false);
    if (pieces.length < 2) return;

    for (var pass = 0; pass < 12; pass++) {
      var moved = false;
      for (var i = 0; i < pieces.length; i++) {
        for (var j = i + 1; j < pieces.length; j++) {
          final a = pieces[i];
          final b = pieces[j];
          final pa = targets[a.id]!;
          final pb = targets[b.id]!;
          final ta = a.copyWith(gridX: pa.x, gridY: pa.y);
          final tb = b.copyWith(gridX: pb.x, gridY: pb.y);
          if (!LayoutCollision.overlaps(ta, tb)) continue;

          final overlapX = math.min(ta.gridX + ta.width, tb.gridX + tb.width) -
              math.max(ta.gridX, tb.gridX);
          final overlapY = math.min(ta.gridY + ta.height, tb.gridY + tb.height) -
              math.max(ta.gridY, tb.gridY);

          if (overlapX <= overlapY) {
            if (ta.gridX <= tb.gridX) {
              final nx = (tb.gridX - ta.width - 0.15).clamp(0.0, cols - ta.width);
              targets[a.id] = (x: nx, y: pa.y);
            } else {
              final nx = (ta.gridX - tb.width - 0.15).clamp(0.0, cols - tb.width);
              targets[b.id] = (x: nx, y: pb.y);
            }
          } else if (ta.gridY <= tb.gridY) {
            final ny = (tb.gridY - ta.height - 0.15).clamp(0.0, rows - ta.height);
            targets[a.id] = (x: pa.x, y: ny);
          } else {
            final ny = (ta.gridY - tb.height - 0.15).clamp(0.0, rows - tb.height);
            targets[b.id] = (x: pb.x, y: ny);
          }
          moved = true;
        }
      }
      if (!moved) break;
    }
  }

  /// Append once when any seated item was re-aimed away from a wall.
  static void noteOrientation(
    List<String> reasons,
    List<FurnitureItem> before,
    List<FurnitureItem> after,
  ) {
    for (int i = 0; i < before.length; i++) {
      final a = after[i];
      if ((before[i].yawDegrees - a.yawDegrees).abs() > 0.01 &&
          (FurnitureShapes.showsFacing(FurnitureShapes.kindOf(a)) || a.id == 'bed')) {
        reasons.add('Turned seating and fans to face into the room — not the wall');
        return;
      }
    }
  }

  static void noteDeskMount(
    List<String> reasons,
    List<FurnitureItem> before,
    List<FurnitureItem> after,
  ) {
    for (var i = 0; i < after.length; i++) {
      final a = after[i];
      if (!SurfaceMounts.isDeskTopItem(a)) continue;
      final host = SurfaceMounts.hostUnder(a, after);
      if (host == null) continue;
      final wasHosted = i < before.length && SurfaceMounts.hostUnder(before[i], before) != null;
      if (!wasHosted) {
        reasons.add('Parked ${a.name} on the ${host.name}');
        return;
      }
    }
  }

  /// Re-assert researched pairings after blend / conflict packing:
  /// chair in front of desk, desk-tops on desk, bed clear of desk, wall storage
  /// flushed to a wall when packing shoved it inland.
  static List<FurnitureItem> relinkPairedLayout({
    required List<FurnitureItem> items,
    required int gridCols,
    required int gridRows,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    var next = items.map((f) => f.copyWith()).toList();
    final door = findDoor(next);
    var desk = findDesk(next);
    final chair = findChair(next);

    // Pin EVERY work desk flush to a side wall with the long edge along the wall.
    next = _orientWorkDesksAlongSideWalls(next, cols: cols, rows: rows);
    desk = findDesk(next);

    // Mount desk-tops BEFORE seating the chair so the PC cannot land in the
    // pull-back corridor after the chair is already placed.
    next = mountDeskTopItems(next, gridCols: gridCols, gridRows: gridRows);
    next = separateDeskTopOverlaps(next);
    desk = findDesk(next);

    if (desk != null && chair != null && !chair.locked) {
      final avoid = next.where((f) => f.id != chair.id).toList();
      final pose = chairInFrontOfDesk(
        desk,
        chair,
        cols: cols,
        rows: rows,
        door: door,
        avoid: avoid,
        alignWith: findMonitor(next),
      );
      final idx = next.indexWhere((f) => f.id == chair.id);
      if (idx >= 0) {
        next[idx] = chair.copyWith(gridX: pose.x, gridY: pose.y);
      }
    }

    next = mountDeskTopItems(next, gridCols: gridCols, gridRows: gridRows);
    next = separateDeskTopOverlaps(next);

    // Push bed away from desk if clearance collapsed during packing.
    if (desk != null) {
      final deskNow = findDesk(next)!;
      for (var i = 0; i < next.length; i++) {
        final f = next[i];
        final h = ItemPlacementRules.hay(f);
        if (!h.contains('bed') || f.locked) continue;
        if (ItemPlacementRules.hasClearGap(
          f,
          deskNow,
          ItemPlacementRules.deskBedClearance,
        )) {
          continue;
        }
        var x = (cols - f.width - 0.15).clamp(0.0, cols - f.width);
        var y = (rows - f.height - 0.15).clamp(0.0, rows - f.height);
        final deskCx = deskNow.gridX + deskNow.width * 0.5;
        if (deskCx > cols * 0.5) {
          x = 0.15.clamp(0.0, cols - f.width);
        }
        // Prefer south of work zone.
        final minY = deskNow.gridY +
            deskNow.height +
            ItemPlacementRules.chairPullback +
            ItemPlacementRules.deskBedClearance;
        if (y < minY) {
          y = minY.clamp(0.0, rows - f.height);
        }
        var trial = f.copyWith(gridX: x, gridY: y);
        if (LayoutCollision.itemCollides(trial, next)) {
          final others = next.where((o) => o.id != f.id).toList();
          final empty = LayoutCollision.findEmptyCell(
            furniture: others,
            gridCols: gridCols,
            gridRows: gridRows,
            width: f.width,
            height: f.height,
            preferWall: true,
          );
          if (empty != null) {
            trial = f.copyWith(gridX: empty.gridX, gridY: empty.gridY);
          }
        }
        next[i] = trial;
      }
    }

    // Flush floating shelves / wardrobes back to a wall.
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      if (ItemPlacementRules.zoneFor(f) != PlacementZone.perimeterWall) continue;
      if (ItemPlacementRules.wallDistance(f, gridCols, gridRows) <=
          ItemPlacementRules.wallFlushTolerance) {
        continue;
      }
      final others = next.where((o) => o.id != f.id).toList();
      final empty = LayoutCollision.findEmptyCell(
        furniture: others,
        gridCols: gridCols,
        gridRows: gridRows,
        width: f.width,
        height: f.height,
        preferWall: true,
      );
      if (empty != null) {
        next[i] = f.copyWith(gridX: empty.gridX, gridY: empty.gridY);
      }
    }

    next = _relinkSofaTvDistance(next, cols, rows);
    next = _relinkWardrobeFrontClearance(next, gridCols, gridRows);
    next = _relinkDeskSideLight(next, cols, rows, gridCols, gridRows);

    // sorting.md hierarchy: hard wall/parent rules beat soft blend floats.
    next = HierarchicalLayout.enforce(
      items: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );

    // Re-seat chair after wall pins may have moved the desk.
    desk = findDesk(next);
    final chairAfter = findChair(next);
    if (desk != null && chairAfter != null && !chairAfter.locked) {
      final avoid = next.where((f) => f.id != chairAfter.id).toList();
      final pose = chairInFrontOfDesk(
        desk,
        chairAfter,
        cols: cols,
        rows: rows,
        door: findDoor(next),
        avoid: avoid,
        alignWith: findMonitor(next),
      );
      final idx = next.indexWhere((f) => f.id == chairAfter.id);
      if (idx >= 0) {
        next[idx] = chairAfter.copyWith(gridX: pose.x, gridY: pose.y);
      }
      next = mountDeskTopItems(next, gridCols: gridCols, gridRows: gridRows);
      next = separateDeskTopOverlaps(next);
    }

    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return List.unmodifiable(next);
  }

  static List<FurnitureItem> _relinkSofaTvDistance(
    List<FurnitureItem> items,
    double cols,
    double rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    FurnitureItem? sofa;
    FurnitureItem? tv;
    for (final f in next) {
      if (ItemPlacementRules.isSofa(f) && !f.locked) sofa ??= f;
      if (ItemPlacementRules.isTv(f) && !f.locked) tv ??= f;
    }
    if (sofa == null || tv == null) return next;
    if (ItemPlacementRules.sofaTvDistanceOk(sofa, tv)) return next;

    final preferred = ItemPlacementRules.sofaTvPreferred;
    final sofaIdx = next.indexWhere((f) => f.id == sofa!.id);
    final tvIdx = next.indexWhere((f) => f.id == tv!.id);
    if (sofaIdx < 0 || tvIdx < 0) return next;

    final s = next[sofaIdx];
    final t = next[tvIdx];
    final sofaY = s.gridY;
    var sofaX = 0.0;
    var sofaCx = sofaX + s.width * 0.5;
    var tvX = (sofaCx + preferred - t.width * 0.5).clamp(0.0, cols - t.width);
    if ((tvX + t.width * 0.5) - sofaCx < preferred - 0.4) {
      tvX = (cols - t.width - 0.1).clamp(0.0, cols - t.width);
      final actualTvCx = tvX + t.width * 0.5;
      sofaX = ((actualTvCx - preferred) - s.width * 0.5).clamp(0.0, cols - s.width);
    }
    next[sofaIdx] = s.copyWith(gridX: sofaX, gridY: sofaY.clamp(0.0, rows - s.height));
    next[tvIdx] = t.copyWith(
      gridX: tvX,
      gridY: sofaY.clamp(0.0, rows - t.height),
    );
    return next;
  }

  static List<FurnitureItem> _relinkWardrobeFrontClearance(
    List<FurnitureItem> items,
    int gridCols,
    int gridRows,
  ) {
    var next = items.map((f) => f.copyWith()).toList();
    for (var wi = 0; wi < next.length; wi++) {
      final wardrobe = next[wi];
      if (wardrobe.locked || !ItemPlacementRules.isWardrobe(wardrobe)) continue;
      if (ItemPlacementRules.hasWardrobeFrontClearance(
        wardrobe,
        next,
        gridCols,
        gridRows,
      )) {
        continue;
      }
      final front = ItemPlacementRules.wardrobeFrontAabb(wardrobe, gridCols, gridRows);
      // Push soft blockers out of the swing volume.
      for (var i = 0; i < next.length; i++) {
        final o = next[i];
        if (o.id == wardrobe.id || o.locked) continue;
        if (SurfaceMounts.isStructuralMount(o) || SurfaceMounts.isDeskTopItem(o)) {
          continue;
        }
        final overlaps = o.gridX < front.maxX &&
            o.gridX + o.width > front.minX &&
            o.gridY < front.maxY &&
            o.gridY + o.height > front.minY;
        if (!overlaps) continue;
        final others = next.where((x) => x.id != o.id).toList();
        final empty = LayoutCollision.findEmptyCell(
          furniture: others,
          gridCols: gridCols,
          gridRows: gridRows,
          width: o.width,
          height: o.height,
          preferInterior: ItemPlacementRules.prefersInterior(o),
          preferWall: ItemPlacementRules.prefersWall(o),
        );
        if (empty != null) {
          next[i] = o.copyWith(gridX: empty.gridX, gridY: empty.gridY);
        }
      }
    }
    return next;
  }

  static List<FurnitureItem> _relinkDeskSideLight(
    List<FurnitureItem> items,
    double cols,
    double rows,
    int gridCols,
    int gridRows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    final window = findWindow(next);
    final desk = findDesk(next);
    final chair = findChair(next);
    if (window == null || desk == null || desk.locked) return next;

    final score = ComfortHeuristics.windowSideLightScore(
      desk: desk,
      chair: chair,
      window: window,
    );
    if (score >= 0.45) return next;

    // Flip desk to the opposite side wall for side-light (OSHA-style guidance).
    final preferEast = desk.gridX + desk.width * 0.5 <= cols * 0.5;
    final deskIdx = next.indexWhere((f) => f.id == desk.id);
    if (deskIdx >= 0) {
      next[deskIdx] = _orientDeskAlongSideWall(
        desk,
        cols: cols,
        rows: rows,
        preferEast: preferEast,
      );
    }
    final deskNow = findDesk(next)!;
    if (chair != null && !chair.locked) {
      final avoid = next.where((f) => f.id != chair.id).toList();
      final pose = chairInFrontOfDesk(
        deskNow,
        chair,
        cols: cols,
        rows: rows,
        door: findDoor(next),
        avoid: avoid,
        alignWith: findMonitor(next),
      );
      final chairIdx = next.indexWhere((f) => f.id == chair.id);
      if (chairIdx >= 0) {
        next[chairIdx] = chair.copyWith(gridX: pose.x, gridY: pose.y);
      }
    }
    return mountDeskTopItems(next);
  }

  static ({bool preferInterior, bool preferWall}) _emptyBiasFor(FurnitureItem mover) {
    if (ItemPlacementRules.prefersWall(mover)) {
      return (preferInterior: false, preferWall: true);
    }
    if (ItemPlacementRules.prefersInterior(mover)) {
      return (preferInterior: true, preferWall: false);
    }
    return (preferInterior: false, preferWall: false);
  }

  /// Final pass every optimizer runs: nudge overlaps and blocked openings apart.
  /// Falls back to [LayoutCollision.findEmptyCell] when tiny nudges cannot clear
  /// hard overlaps (the bed/sofa stack case on small grids).
  static List<FurnitureItem> resolveLayoutConflicts({
    required List<FurnitureItem> items,
    required int gridCols,
    required int gridRows,
    int maxPasses = 16,
  }) {
    final cols = gridCols.toDouble();
    final rows = gridRows.toDouble();
    final mutable = items.map((f) => f.copyWith()).toList();

    for (var pass = 0; pass < maxPasses; pass++) {
      var moved = false;
      final conflicts = LayoutCollision.findConflicts(
        furniture: mutable,
        gridCols: gridCols,
        gridRows: gridRows,
      );

      for (final conflict in conflicts) {
        if (conflict.kind != LayoutConflictKind.overlap &&
            conflict.kind != LayoutConflictKind.blockedOpening) {
          continue;
        }

        FurnitureItem? mover;
        for (final id in conflict.itemIds) {
          final hay = id.toLowerCase();
          if (hay.contains('door') || hay.contains('window')) continue;
          final idx = mutable.indexWhere((f) => f.id == id);
          if (idx < 0) continue;
          final item = mutable[idx];
          if (item.locked || SurfaceMounts.isStructuralMount(item)) continue;
          if (PlacementCatalog.isImmovableInConflicts(item)) continue;
          if (SurfaceMounts.isVent(item) ||
              SurfaceMounts.isDoor(item) ||
              SurfaceMounts.isWindow(item)) {
            continue;
          }
          // Keep the chair glued to the desk — move the other piece instead.
          if (ItemPlacementRules.hay(item).contains('chair') &&
              findDesk(mutable) != null) {
            continue;
          }
          // Keep the desk on its wall — move the colliding soft piece instead.
          if (SurfaceMounts.isDeskHost(item) &&
              ItemPlacementRules.hay(item).contains('desk')) {
            continue;
          }
          // Prefer moving the larger soft piece when bed/sofa fight.
          if (mover == null ||
              item.width * item.height > mover.width * mover.height) {
            mover = item;
          }
        }
        if (mover == null) continue;

        final idx = mutable.indexWhere((f) => f.id == mover!.id);
        final item = mutable[idx];
        final maxX = (cols - item.width).clamp(0.0, cols);
        final maxY = (rows - item.height).clamp(0.0, rows);

        var nx = (item.gridX + 0.5).clamp(0.0, maxX);
        var ny = (item.gridY - 0.6).clamp(0.0, maxY);
        if ((ny - item.gridY).abs() < 0.01) {
          ny = (item.gridY + 0.6).clamp(0.0, maxY);
        }
        if ((nx - item.gridX).abs() < 0.01 && (ny - item.gridY).abs() < 0.01) {
          nx = (item.gridX - 0.5).clamp(0.0, maxX);
        }

        var resolved = LayoutCollision.resolveMove(
          id: item.id,
          proposedX: nx,
          proposedY: ny,
          furniture: mutable,
          gridCols: gridCols,
          gridRows: gridRows,
        );

        // Hard fallback: pick a free cell so overlaps cannot stick.
        final trial = item.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
        if (LayoutCollision.itemCollides(trial, mutable)) {
          final others = mutable.where((f) => f.id != item.id).toList(growable: false);
          final bias = _emptyBiasFor(item);
          final empty = LayoutCollision.findEmptyCell(
            furniture: others,
            gridCols: gridCols,
            gridRows: gridRows,
            width: item.width,
            height: item.height,
            preferInterior: bias.preferInterior,
            preferWall: bias.preferWall,
          );
          if (empty != null) {
            resolved = LayoutMoveResult(gridX: empty.gridX, gridY: empty.gridY);
          }
        }

        if ((resolved.gridX - item.gridX).abs() > 0.01 ||
            (resolved.gridY - item.gridY).abs() > 0.01) {
          mutable[idx] = item.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
          moved = true;
        }
      }

      if (!moved) break;
    }

    return ensureNoHardOverlaps(
      items: mutable,
      gridCols: gridCols,
      gridRows: gridRows,
    );
  }

  /// Last-resort pack: every hard overlap relocates a movable piece to an empty cell.
  static List<FurnitureItem> ensureNoHardOverlaps({
    required List<FurnitureItem> items,
    required int gridCols,
    required int gridRows,
    int maxPasses = 32,
    bool relinkPairs = true,
  }) {
    var mutable = mountDeskTopItems(items).map((f) => f.copyWith()).toList();
    mutable = separateDeskTopOverlaps(mutable);

    for (var pass = 0; pass < maxPasses; pass++) {
      final conflicts = LayoutCollision.findConflicts(
        furniture: mutable,
        gridCols: gridCols,
        gridRows: gridRows,
      ).where(
        (c) =>
            c.kind == LayoutConflictKind.overlap ||
            c.kind == LayoutConflictKind.blockedOpening,
      ).toList(growable: false);
      if (conflicts.isEmpty) break;

      var moved = false;
      for (final conflict in conflicts) {
        // Try smaller movers first — more likely to find a free cell.
        final candidates = <FurnitureItem>[];
        for (final id in conflict.itemIds) {
          final idx = mutable.indexWhere((f) => f.id == id);
          if (idx < 0) continue;
          final item = mutable[idx];
          if (item.locked || SurfaceMounts.isStructuralMount(item)) continue;
          if (PlacementCatalog.isImmovableInConflicts(item)) continue;
          // Prefer not to orphan the chair from the desk during packing.
          if (ItemPlacementRules.hay(item).contains('chair') &&
              findDesk(mutable) != null) {
            continue;
          }
          if (SurfaceMounts.isDeskHost(item) &&
              ItemPlacementRules.hay(item).contains('desk')) {
            continue;
          }
          candidates.add(item);
        }
        // If only the chair was conflicting, allow moving it as last resort.
        if (candidates.isEmpty) {
          for (final id in conflict.itemIds) {
            final idx = mutable.indexWhere((f) => f.id == id);
            if (idx < 0) continue;
            final item = mutable[idx];
            if (item.locked || SurfaceMounts.isStructuralMount(item)) continue;
            candidates.add(item);
          }
        }
        candidates.sort(
          (a, b) => (a.width * a.height).compareTo(b.width * b.height),
        );

        for (final mover in candidates) {
          final idx = mutable.indexWhere((f) => f.id == mover.id);
          final others = mutable.where((f) => f.id != mover.id).toList(growable: false);
          final bias = _emptyBiasFor(mover);
          var empty = LayoutCollision.findEmptyCell(
            furniture: others,
            gridCols: gridCols,
            gridRows: gridRows,
            width: mover.width,
            height: mover.height,
            preferInterior: bias.preferInterior,
            preferWall: bias.preferWall,
          );

          // Overfull room: temporarily park a smaller unlocked piece aside,
          // seat the mover, then re-seat the evictee.
          if (empty == null) {
            final evictable = others
                .where(
                  (f) =>
                      !f.locked &&
                      !SurfaceMounts.isStructuralMount(f) &&
                      !SurfaceMounts.isDeskTopItem(f) &&
                      f.width * f.height <= mover.width * mover.height &&
                      f.id != mover.id,
                )
                .toList()
              ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
            for (final victim in evictable) {
              final withoutVictim = others.where((f) => f.id != victim.id).toList();
              final victimBias = _emptyBiasFor(mover);
              final seat = LayoutCollision.findEmptyCell(
                furniture: withoutVictim,
                gridCols: gridCols,
                gridRows: gridRows,
                width: mover.width,
                height: mover.height,
                preferInterior: victimBias.preferInterior,
                preferWall: victimBias.preferWall,
              );
              if (seat == null) continue;
              final victimIdx = mutable.indexWhere((f) => f.id == victim.id);
              mutable[idx] = mover.copyWith(gridX: seat.gridX, gridY: seat.gridY);
              final afterMover = mutable.where((f) => f.id != victim.id).toList();
              final evictBias = _emptyBiasFor(victim);
              final victimSeat = LayoutCollision.findEmptyCell(
                furniture: afterMover,
                gridCols: gridCols,
                gridRows: gridRows,
                width: victim.width,
                height: victim.height,
                preferInterior: evictBias.preferInterior,
                preferWall: evictBias.preferWall,
              );
              if (victimSeat != null) {
                mutable[victimIdx] = victim.copyWith(
                  gridX: victimSeat.gridX,
                  gridY: victimSeat.gridY,
                );
              } else {
                // Put victim back; try next.
                mutable[idx] = mover;
                continue;
              }
              moved = true;
              empty = seat;
              break;
            }
          }

          if (empty == null) continue;
          if (!moved) {
            final placed = mover.copyWith(gridX: empty.gridX, gridY: empty.gridY);
            mutable[idx] = placed;
            moved = true;
          }
          break;
        }
      }
      if (!moved) break;
    }

    mutable = separateDeskTopOverlaps(mutable);
    if (!relinkPairs) {
      // Keep chair glued after the post-relink sweep.
      return List.unmodifiable(
        _snapChairAndDesktop(
          mutable,
          gridCols: gridCols,
          gridRows: gridRows,
        ),
      );
    }

    final linked = relinkPairedLayout(
      items: mutable,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    // Clear overlaps introduced by relink without looping forever.
    return ensureNoHardOverlaps(
      items: linked,
      gridCols: gridCols,
      gridRows: gridRows,
      maxPasses: maxPasses,
      relinkPairs: false,
    );
  }

  static List<FurnitureItem> _snapChairAndDesktop(
    List<FurnitureItem> items, {
    required int gridCols,
    required int gridRows,
  }) {
    var next = items.map((f) => f.copyWith()).toList();
    var desk = findDesk(next);
    final chair = findChair(next);
    final door = findDoor(next);
    if (desk != null && !desk.locked) {
      final preferEast = desk.gridX + desk.width * 0.5 > gridCols * 0.5;
      final pinned = _pinDeskToSideWall(
        desk: desk,
        x: desk.gridX,
        y: desk.gridY,
        cols: gridCols.toDouble(),
        rows: gridRows.toDouble(),
        preferEast: preferEast,
      );
      final idx = next.indexWhere((f) => f.id == desk!.id);
      if (idx >= 0) {
        next[idx] = desk.copyWith(gridX: pinned.x, gridY: pinned.y);
        desk = next[idx];
      }
    }
    // Flush every other work desk too.
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked || !_isWorkDesk(f)) continue;
      if (desk != null && f.id == desk.id) continue;
      final preferEast = f.gridX + f.width * 0.5 > gridCols * 0.5;
      final pinned = _pinDeskToSideWall(
        desk: f,
        x: f.gridX,
        y: f.gridY,
        cols: gridCols.toDouble(),
        rows: gridRows.toDouble(),
        preferEast: preferEast,
      );
      next[i] = f.copyWith(gridX: pinned.x, gridY: pinned.y);
    }
    next = mountDeskTopItems(next);
    next = separateDeskTopOverlaps(next);
    desk = findDesk(next);
    if (desk != null && chair != null && !chair.locked) {
      final avoid = next.where((f) => f.id != chair.id).toList();
      final pose = chairInFrontOfDesk(
        desk,
        chair,
        cols: gridCols.toDouble(),
        rows: gridRows.toDouble(),
        door: door,
        avoid: avoid,
        alignWith: findMonitor(next),
      );
      final trial = chair.copyWith(gridX: pose.x, gridY: pose.y);
      final blocksOpening = next.any((other) {
        if (other.id == chair.id) return false;
        final oh = '${other.id} ${other.name} ${other.iconName}'.toLowerCase();
        if (!(oh.contains('door') || oh.contains('window'))) return false;
        return LayoutCollision.overlaps(trial, other);
      });
      if (!LayoutCollision.itemCollides(trial, next) && !blocksOpening) {
        final idx = next.indexWhere((f) => f.id == chair.id);
        if (idx >= 0) next[idx] = trial;
      }
    }
    next = mountDeskTopItems(next);
    next = separateDeskTopOverlaps(next);
    return next;
  }
}
