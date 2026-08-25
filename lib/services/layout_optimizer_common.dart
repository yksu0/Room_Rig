// lib/services/layout_optimizer_common.dart
// Shared Auto-Rig placement helpers.
//
// Rules encoded here follow widely cited practice, not ad-hoc demo poses:
// - ISO 9241-5 / BIFMA G1: chair centered on desk with ~0.9 m pull-back;
//   monitor on the desk midline facing the user; task light beside the screen.
// - IES / WELL daylight: desk in the daylight band but offset off the window
//   axis so the user is not square-on to glare.
// - ASHRAE throw guidance: keep large blockers out of the primary AC cone;
//   put heat sources inside the cooled volume; aim fans into open floor.
// - Egress: leave a clear approach strip at the door.
import 'dart:math' as math;

import '../models/room_model.dart';
import '../models/surface_mount.dart';
import '../widgets/furniture_shapes.dart';
import 'ergonomics_simulator.dart';
import 'layout_collision.dart';
import 'layout_orientation.dart';

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

  /// Chair pull-back used across Auto-Rig (≈ ISO seated knee clearance).
  static const chairPullback = ErgonomicsSimulator.idealChairGap;

  /// Minimum clear cells in front of a door (egress approach).
  static const doorApproachDepth = 1.2;

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

    next = mountDeskTopItems(next);
    next = LayoutOrientation.apply(
      furniture: next,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    return next;
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
    final hosts = furniture.where(SurfaceMounts.isDeskHost).toList();
    if (hosts.isEmpty) return null;
    hosts.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return hosts.first;
  }

  static FurnitureItem? findChair(List<FurnitureItem> furniture) =>
      firstWhere(furniture, (f) {
        final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
        return f.iconName == 'chair' || hay.contains('chair') || hay.contains('seat');
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
    final seatedDesk = desk.copyWith(gridX: deskPose.x, gridY: deskPose.y);

    switch (bias) {
      case WorkClusterBias.airflow:
        reasons.add('Placed desk inside the cooled work zone (ASHRAE throw band)');
      case WorkClusterBias.lighting:
        reasons.add('Desk in daylight band, offset off-axis to cut glare (IES)');
      case WorkClusterBias.ergonomics:
        reasons.add('Anchored desk with clear approach and pull-back (ISO 9241-5)');
    }

    final chair = findChair(furniture);
    if (chair != null) {
      targets[chair.id] = chairInFrontOfDesk(
        seatedDesk,
        chair,
        cols: cols,
        rows: rows,
      );
      reasons.add('Centered chair on the desk with ~${chairPullback.toStringAsFixed(1)} m pull-back');
    }

    var mountedAny = false;
    for (final f in furniture) {
      if (!SurfaceMounts.isDeskTopItem(f) || f.locked) continue;
      targets[f.id] = deskTopTarget(seatedDesk, f);
      mountedAny = true;
    }
    if (mountedAny) {
      reasons.add('Monitor / PC / task lamp on the desk surface — not the floor');
    }

    return reasons;
  }

  /// Chair centered on the desk front edge (user faces the task surface).
  static ({double x, double y}) chairInFrontOfDesk(
    FurnitureItem desk,
    FurnitureItem chair, {
    required double cols,
    required double rows,
  }) {
    final x = desk.gridX + (desk.width - chair.width) * 0.5;
    final y = desk.gridY + desk.height + chairPullback - chair.height * 0.15;
    final maxX = (cols - chair.width).clamp(0.0, cols);
    final maxY = (rows - chair.height).clamp(0.0, rows);
    return (x: x.clamp(0.0, maxX), y: y.clamp(0.0, maxY));
  }

  static ({double x, double y}) _deskPose({
    required FurnitureItem desk,
    required FurnitureItem? window,
    required FurnitureItem? door,
    required double cols,
    required double rows,
    required WorkClusterBias bias,
  }) {
    late double x;
    late double y;
    switch (bias) {
      case WorkClusterBias.airflow:
        // Left / mid-depth — inside typical wall-AC throw from the long wall.
        x = 0.35;
        y = (rows * 0.28).clamp(1.0, rows - desk.height - 2.2);
      case WorkClusterBias.lighting:
        // Daylight band (~2 m from north window) but offset off the axis.
        final windowX = window != null ? window.gridX + window.width * 0.5 : cols * 0.4;
        x = (windowX - desk.width * 0.65 - 0.4).clamp(0.3, cols - desk.width - 0.3);
        y = 2.0.clamp(1.2, rows - desk.height - 2.0);
      case WorkClusterBias.ergonomics:
        // Stable left work wall with room for chair pull-back + side aisle.
        x = 0.8.clamp(0.2, cols - desk.width - 0.5);
        y = 1.8.clamp(1.0, rows - desk.height - chairPullback - 1.2);
    }

    // Keep desk out of the door approach strip when possible.
    if (door != null) {
      final approach = _doorApproachRect(door, cols, rows);
      final trial = desk.copyWith(gridX: x, gridY: y);
      if (LayoutCollision.overlaps(trial, approach)) {
        if (door.gridX < cols * 0.5) {
          x = math.max(x, door.gridX + door.width + doorApproachDepth);
        } else {
          x = math.min(x, door.gridX - desk.width - 0.2);
        }
      }
    }

    final maxX = (cols - desk.width).clamp(0.0, cols);
    final maxY = (rows - desk.height).clamp(0.0, rows);
    return (x: x.clamp(0.0, maxX), y: y.clamp(0.0, maxY));
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
  static List<FurnitureItem> mountDeskTopItems(List<FurnitureItem> furniture) {
    final hosts = furniture.where(SurfaceMounts.isDeskHost).toList();
    if (hosts.isEmpty) return furniture;

    hosts.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final primary = hosts.first;

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
      final item = next[i];
      final host = SurfaceMounts.hostUnder(item, next) ?? primary;
      final others = placedOnHost.putIfAbsent(host.id, () => <FurnitureItem>[]);
      final slot = _deskSlot(
        host: host,
        item: item,
        alreadyOnHost: others,
        rank: _deskItemRank(item),
      );
      final seated = item.copyWith(gridX: slot.$1, gridY: slot.$2);
      next[i] = seated;
      others.add(seated);
    }
    return next;
  }

  /// Target pose on [host] for a desk-top item (used by domain optimizers).
  static ({double x, double y}) deskTopTarget(FurnitureItem host, FurnitureItem item) {
    final slot = _deskSlot(
      host: host,
      item: item,
      alreadyOnHost: const [],
      rank: _deskItemRank(item),
    );
    return (x: slot.$1, y: slot.$2);
  }

  static int _deskItemRank(FurnitureItem f) {
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    if (hay.contains('monitor') || hay.contains('screen') || hay.contains('display')) {
      return 0;
    }
    if (hay.contains('pc') || hay.contains('tower') || hay.contains('computer')) {
      return 1;
    }
    return 2; // lamp / other desk-top
  }

  /// Desk-top slots (viewed with chair on the +Z / higher gridY side):
  /// - Monitor: back edge, centered — arm's-length task plane facing the user
  /// - PC: left rear — keeps cables short without blocking the screen
  /// - Lamp: right of monitor — side lighting reduces screen glare (IES)
  static (double, double) _deskSlot({
    required FurnitureItem host,
    required FurnitureItem item,
    required List<FurnitureItem> alreadyOnHost,
    required int rank,
  }) {
    final maxX = host.gridX + host.width - item.width;
    final maxY = host.gridY + host.height - item.height;
    final loX = host.gridX;
    final loY = host.gridY;
    final hiX = math.max(loX, maxX);
    final hiY = math.max(loY, maxY);

    late double preferX;
    late double preferY;
    switch (rank) {
      case 0: // monitor — back edge, centered
        preferX = host.gridX + (host.width - item.width) * 0.5;
        preferY = host.gridY;
      case 1: // PC — left rear of the surface
        preferX = host.gridX;
        preferY = host.gridY;
      default: // lamp — right of the work surface
        preferX = hiX;
        preferY = host.gridY + (host.height - item.height) * 0.35;
    }
    preferX = preferX.clamp(loX, hiX);
    preferY = preferY.clamp(loY, hiY);

    var x = preferX;
    var y = preferY;
    for (var attempt = 0; attempt < 16; attempt++) {
      final candidate = item.copyWith(gridX: x, gridY: y);
      final clash = alreadyOnHost.any((o) => LayoutCollision.overlaps(candidate, o));
      if (!clash) return (x, y);
      x = (x + 0.25).clamp(loX, hiX);
      if ((x - preferX).abs() < 0.01 || x >= hiX - 0.01) {
        y = (y + 0.25).clamp(loY, hiY);
        x = preferX;
      }
    }
    return (preferX, preferY);
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
        var x = (cols - f.width - 0.2).clamp(0.0, cols - f.width);
        var y = (rows - f.height - 0.25).clamp(0.0, rows - f.height);
        // Keep bed off the chair pull-back when a desk exists.
        if (desk != null) {
          final deskY = targets[desk.id]?.y ?? desk.gridY;
          final pullEnd = deskY + desk.height + chairPullback + 0.4;
          if (y < pullEnd) y = (rows - f.height - 0.2).clamp(pullEnd, rows - f.height);
        }
        targets[f.id] = (x: x, y: y);
        reasons.add('Bed on the far wall — clear of the work / circulation zone');
      } else if (hay.contains('shelf') || hay.contains('book') || hay.contains('wardrobe')) {
        // Tall storage in a corner, out of daylight + AC throw corridor.
        final onRight = door == null || door.gridX < cols * 0.5;
        targets[f.id] = (
          x: onRight ? (cols - f.width).clamp(0.0, cols - f.width) : 0.0,
          y: (rows - f.height - 0.4).clamp(2.0, rows - f.height),
        );
        if (!reasons.any((r) => r.contains('storage'))) {
          reasons.add('Tall storage in a perimeter corner — out of throw / daylight lanes');
        }
      } else if (hay.contains('sofa') || hay.contains('couch')) {
        targets[f.id] = (
          x: 0.4.clamp(0.0, cols - f.width),
          y: (rows - f.height - 0.3).clamp(0.0, rows - f.height),
        );
        if (!reasons.any((r) => r.contains('Sofa'))) {
          reasons.add('Sofa on the opposite wall from the bed — lounge zone stays open');
        }
      } else if (hay.contains('plant')) {
        targets[f.id] = (x: (cols - f.width).clamp(0.0, cols - f.width), y: 2.0);
      }
    }

    _separateOverlappingTargets(furniture, targets, cols, rows);
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

  /// Final pass every optimizer runs: nudge overlaps and blocked openings apart.
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
        if (SurfaceMounts.isVent(item) ||
            SurfaceMounts.isDoor(item) ||
            SurfaceMounts.isWindow(item)) {
          continue;
        }
        mover = item;
          break;
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

        final resolved = LayoutCollision.resolveMove(
          id: item.id,
          proposedX: nx,
          proposedY: ny,
          furniture: mutable,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        if ((resolved.gridX - item.gridX).abs() > 0.01 ||
            (resolved.gridY - item.gridY).abs() > 0.01) {
          mutable[idx] = item.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
          moved = true;
        }
      }

      if (!moved) break;
    }

    return List.unmodifiable(mutable);
  }
}
