// Hierarchical Auto-Rig enforcement from sorting.md + sorting_response.md.
// Hard wall/parent rules run AFTER soft goal blending so floats cannot stick.
// Prefer data-driven catalog rules; keep special cases only where candidate
// search is genuinely richer (bed, sofa↔TV).
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'item_placement_rules.dart';
import 'layout_collision.dart';
import 'placement_catalog.dart';

class HierarchicalLayout {
  HierarchicalLayout._();

  static const wallTol = 0.08;

  /// Apply catalog hard rules in class order. Call after blend / packing.
  static List<FurnitureItem> enforce({
    required List<FurnitureItem> items,
    required int gridCols,
    required int gridRows,
  }) {
    var next = items.map((f) => f.copyWith()).toList();
    next = _pinMustWallAnchors(next, gridCols, gridRows);
    next = _pinPreferredWallMajors(next, gridCols, gridRows);
    next = _pinBedHeadboard(next, gridCols, gridRows);
    next = _placeSofaCandidates(next, gridCols, gridRows);
    next = _centerCeilingLights(next, gridCols, gridRows);
    next = _placePortableAcNearWindow(next, gridCols, gridRows);
    next = _attachPhysicalChildren(next, gridCols, gridRows);
    next = _nudgePcVentilation(next, gridCols, gridRows);
    next = _pushForbiddenOffWall(next, gridCols, gridRows);
    next = _clearSoftOverlaps(next, gridCols, gridRows);
    return next;
  }

  /// Move Class C/D accents that landed on top of majors after wall pins.
  static List<FurnitureItem> _clearSoftOverlaps(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    var next = items.map((f) => f.copyWith()).toList();
    for (var pass = 0; pass < 8; pass++) {
      var moved = false;
      for (var i = 0; i < next.length; i++) {
        final f = next[i];
        if (f.locked || PlacementCatalog.isImmovableInConflicts(f)) continue;
        final spec = PlacementCatalog.of(f);
        if (spec.klass == PlacementClass.aAnchor) continue;
        final preferMove = spec.klass == PlacementClass.cPeripheral ||
            spec.klass == PlacementClass.dClimate ||
            spec.klass == PlacementClass.eAttached;
        if (!preferMove && spec.klass == PlacementClass.bMajor) continue;
        if (!LayoutCollision.itemCollides(f, next)) continue;
        final others = next.where((o) => o.id != f.id).toList();
        final empty = LayoutCollision.findEmptyCell(
          furniture: others,
          gridCols: cols,
          gridRows: rows,
          width: f.width,
          height: f.height,
          preferInterior: spec.wall == WallRequirement.forbidden,
          preferWall: spec.wall == WallRequirement.preferred ||
              spec.wall == WallRequirement.allowed,
        );
        if (empty != null) {
          next[i] = f.copyWith(gridX: empty.gridX, gridY: empty.gridY);
          moved = true;
        } else {
          outer:
          for (final dy in const [-1.0, 1.0, -2.0, 2.0, 0.0]) {
            for (final dx in const [-1.0, 1.0, -2.0, 2.0, 0.0]) {
              if (dx == 0 && dy == 0) continue;
              final tx = (f.gridX + dx).clamp(0.0, cols - f.width);
              final ty = (f.gridY + dy).clamp(0.0, rows - f.height);
              final trial = f.copyWith(gridX: tx, gridY: ty);
              if (!LayoutCollision.itemCollides(trial, others)) {
                next[i] = trial;
                moved = true;
                break outer;
              }
            }
          }
        }
      }
      if (!moved) break;
    }
    return next;
  }

  static bool touchesWall(FurnitureItem f, int cols, int rows, {double tol = wallTol}) {
    return ItemPlacementRules.wallDistance(f, cols, rows) <= tol;
  }

  static int wallTouchCount(FurnitureItem f, int cols, int rows, {double tol = wallTol}) {
    var n = 0;
    if (f.gridX <= tol) n++;
    if (f.gridY <= tol) n++;
    if (cols - (f.gridX + f.width) <= tol) n++;
    if (rows - (f.gridY + f.height) <= tol) n++;
    return n;
  }

  /// Bed: candidate wall/corner poses — never free float.
  static List<FurnitureItem> _pinBedHeadboard(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    final desk = _findByKind(next, 'desk');
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      if (PlacementCatalog.of(f).id != 'bed' && !ItemPlacementRules.hay(f).contains('bed')) {
        continue;
      }
      if (touchesWall(f, cols, rows) &&
          (desk == null ||
              ItemPlacementRules.hasClearGap(f, desk, ItemPlacementRules.deskBedClearance))) {
        continue;
      }
      final best = _bestBedPose(f, desk, next, cols, rows);
      if (best != null) next[i] = f.copyWith(gridX: best.x, gridY: best.y);
    }
    return next;
  }

  static ({double x, double y})? _bestBedPose(
    FurnitureItem bed,
    FurnitureItem? desk,
    List<FurnitureItem> all,
    int cols,
    int rows,
  ) {
    final c = cols.toDouble();
    final r = rows.toDouble();
    final w = bed.width;
    final h = bed.height;
    final candidates = <({double x, double y, int walls, double score})>[
      (x: 0.0, y: 0.0, walls: 2, score: 0),
      (x: (c - w).clamp(0.0, c - w), y: 0.0, walls: 2, score: 0),
      (x: 0.0, y: (r - h).clamp(0.0, r - h), walls: 2, score: 3),
      (x: (c - w).clamp(0.0, c - w), y: (r - h).clamp(0.0, r - h), walls: 2, score: 4),
      (x: ((c - w) * 0.5).clamp(0.0, c - w), y: 0.0, walls: 1, score: 1),
      (x: ((c - w) * 0.5).clamp(0.0, c - w), y: (r - h).clamp(0.0, r - h), walls: 1, score: 2),
      (x: 0.0, y: ((r - h) * 0.5).clamp(0.0, r - h), walls: 1, score: 1),
      (x: (c - w).clamp(0.0, c - w), y: ((r - h) * 0.5).clamp(0.0, r - h), walls: 1, score: 1),
    ];

    ({double x, double y, int walls, double score})? best;
    for (final cand in candidates) {
      final trial = bed.copyWith(gridX: cand.x, gridY: cand.y);
      if (LayoutCollision.itemCollides(trial, all)) continue;
      if (desk != null &&
          !ItemPlacementRules.hasClearGap(
            trial,
            desk,
            ItemPlacementRules.deskBedClearance * 0.85,
          )) {
        continue;
      }
      final scored = (
        x: cand.x,
        y: cand.y,
        walls: cand.walls,
        score: cand.score + cand.walls * 2 + cand.y * 0.15,
      );
      if (best == null || scored.score > best.score) best = scored;
    }
    if (best == null) return null;
    return (x: best.x, y: best.y);
  }

  /// Sofa: wall preferred, not mandatory — score wall / floating / TV pairing.
  static List<FurnitureItem> _placeSofaCandidates(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    FurnitureItem? tv;
    for (final f in next) {
      if (ItemPlacementRules.hay(f).contains('tv')) {
        tv = f;
        break;
      }
    }
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked || !ItemPlacementRules.isSofa(f)) continue;

      final c = cols.toDouble();
      final r = rows.toDouble();
      final w = f.width;
      final h = f.height;
      final candidates = <({double x, double y})>[
        (x: f.gridX, y: f.gridY), // keep current (may already be floating)
        (x: 0.0, y: (r * 0.38).clamp(0.0, r - h)),
        (x: (c - w).clamp(0.0, c - w), y: (r * 0.38).clamp(0.0, r - h)),
        (x: ((c - w) * 0.5).clamp(0.0, c - w), y: (r - h).clamp(0.0, r - h)),
        (x: 0.0, y: (r - h).clamp(0.0, r - h)),
        (x: (c - w).clamp(0.0, c - w), y: (r - h).clamp(0.0, r - h)),
        // Floating lounge — valid when TV distance / circulation wins.
        (x: (c * 0.25).clamp(0.0, c - w), y: (r * 0.4).clamp(0.0, r - h)),
        (x: (c * 0.45).clamp(0.0, c - w), y: (r * 0.45).clamp(0.0, r - h)),
      ];

      ({double x, double y})? best;
      var bestScore = -1e9;
      for (final cand in candidates) {
        final trial = f.copyWith(gridX: cand.x, gridY: cand.y);
        if (LayoutCollision.itemCollides(trial, next)) continue;
        var score = 0.0;
        score += wallTouchCount(trial, cols, rows) * 1.4; // preferred, not forced
        if (tv != null) {
          final dist = ItemPlacementRules.sofaTvCenterDistance(trial, tv);
          final pref = ItemPlacementRules.sofaTvPreferred;
          final err = (dist - pref).abs();
          score += 4.0 - (err / (pref + 0.01)).clamp(0.0, 4.0);
        } else {
          score += 0.5; // mild wall preference when no TV
        }
        // Prefer not blocking the door band (north openings common).
        if (trial.gridY < 1.2 && trial.gridX + trial.width > cols * 0.35) {
          score -= 1.2;
        }
        if (score > bestScore) {
          bestScore = score;
          best = cand;
        }
      }
      if (best != null) {
        next[i] = f.copyWith(gridX: best.x, gridY: best.y);
      }
    }
    return next;
  }

  static List<FurnitureItem> _pinMustWallAnchors(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      final spec = PlacementCatalog.of(f);
      if (spec.wall != WallRequirement.must) continue;
      if (touchesWall(f, cols, rows)) continue;
      next[i] = SurfaceMounts.snapToWall(
        f,
        gridCols: cols,
        gridRows: rows,
        preferred: SurfaceMounts.nearestWall(f, gridCols: cols, gridRows: rows),
      );
    }
    return next;
  }

  static List<FurnitureItem> _pinPreferredWallMajors(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      final spec = PlacementCatalog.of(f);
      if (spec.wall != WallRequirement.preferred) continue;
      if (spec.id == 'bed' || spec.id == 'sofa') continue;
      if (ItemPlacementRules.isSofa(f)) continue;
      if (touchesWall(f, cols, rows)) continue;
      if (SurfaceMounts.isDeskHost(f) || ItemPlacementRules.hay(f).contains('desk')) {
        // Desk side-wall flush is owned by relinkPairedLayout.
        continue;
      }
      final snapped = SurfaceMounts.snapToWall(
        f,
        gridCols: cols,
        gridRows: rows,
        preferred: SurfaceMounts.nearestWall(f, gridCols: cols, gridRows: rows),
      );
      if (!LayoutCollision.itemCollides(snapped, next.where((o) => o.id != f.id).toList())) {
        next[i] = snapped;
      } else {
        final others = next.where((o) => o.id != f.id).toList();
        final empty = LayoutCollision.findEmptyCell(
          furniture: others,
          gridCols: cols,
          gridRows: rows,
          width: f.width,
          height: f.height,
          preferWall: true,
        );
        if (empty != null) {
          next[i] = f.copyWith(gridX: empty.gridX, gridY: empty.gridY);
        }
      }
    }
    return next;
  }

  static List<FurnitureItem> _centerCeilingLights(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      final spec = PlacementCatalog.of(f);
      if (spec.surface != PlacementSurface.ceiling &&
          !ItemPlacementRules.hay(f).contains('ceiling')) {
        continue;
      }
      if (f.locked) continue;
      next[i] = f.copyWith(
        gridX: (cols * 0.5 - f.width * 0.5).clamp(0.0, cols - f.width),
        gridY: (rows * 0.45 - f.height * 0.5).clamp(0.0, rows - f.height),
      );
    }
    return next;
  }

  /// Portable AC: near window with hose path — mid-room scores poorly.
  static List<FurnitureItem> _placePortableAcNearWindow(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    FurnitureItem? window;
    for (final o in next) {
      if (SurfaceMounts.isWindow(o)) {
        window = o;
        break;
      }
    }
    if (window == null) return next;
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      final spec = PlacementCatalog.of(f);
      if (spec.id != 'portable_ac' && !ItemPlacementRules.hay(f).contains('portable')) {
        continue;
      }
      if (f.locked) continue;
      final wx = window.gridX.clamp(0.0, cols - f.width);
      final wy = (window.gridY + window.height * 0.15).clamp(0.0, rows - f.height);
      // Prefer just inside the window wall.
      final candidates = <({double x, double y})>[
        (x: wx, y: wy),
        (x: (window.gridX + 0.15).clamp(0.0, cols - f.width), y: wy),
        (x: wx, y: (window.gridY + 1.0).clamp(0.0, rows - f.height)),
      ];
      for (final cand in candidates) {
        final trial = f.copyWith(gridX: cand.x, gridY: cand.y);
        if (!LayoutCollision.itemCollides(trial, next)) {
          next[i] = trial;
          break;
        }
      }
    }
    return next;
  }

  /// Only true physical children (Class E / physicalParent).
  static List<FurnitureItem> _attachPhysicalChildren(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    var next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      final spec = PlacementCatalog.of(f);
      if (spec.physicalParent == 'window' || ItemPlacementRules.hay(f).contains('blind')) {
        FurnitureItem? window;
        for (final o in next) {
          if (SurfaceMounts.isWindow(o)) {
            window = o;
            break;
          }
        }
        if (window != null && !f.locked) {
          next[i] = f.copyWith(
            gridX: window.gridX.clamp(0.0, cols - f.width),
            gridY: window.gridY.clamp(0.0, rows - f.height),
          );
        }
        continue;
      }
      // Physical desk mounts + spatial desk-tops (monitor/PC/lamp) still ride host.
      final onDesk = spec.physicalParent == 'desk' ||
          spec.spatialParent == 'desk' ||
          SurfaceMounts.isDeskTopItem(f);
      if (!onDesk) continue;
      if (ItemPlacementRules.hay(f).contains('chair')) continue;
      next[i] = SurfaceMounts.snapOntoHost(f, next);
    }
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (!ItemPlacementRules.hay(f).contains('mat')) continue;
      if (f.locked) continue;
      final chair = next.where((o) => ItemPlacementRules.hay(o).contains('chair')).firstOrNull;
      final desk = _findByKind(next, 'desk');
      if (chair != null) {
        next[i] = f.copyWith(gridX: chair.gridX, gridY: chair.gridY);
      } else if (desk != null) {
        next[i] = f.copyWith(
          gridX: desk.gridX,
          gridY: (desk.gridY + desk.height).clamp(0.0, rows - f.height),
        );
      }
    }
    return next;
  }

  /// Keep PC side vents from sitting flush against wall / tall furniture.
  static List<FurnitureItem> _nudgePcVentilation(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      final spec = PlacementCatalog.of(f);
      if (spec.id != 'pc' || spec.ventClearance <= 0) continue;
      final blocked = PlacementCatalog.pcVentilationBlockRatio(f, next, cols, rows);
      if (blocked < 0.4) continue;
      final host = SurfaceMounts.hostUnder(f, next);
      if (host == null) continue;
      final need = spec.ventClearance;
      final tries = <({double x, double y})>[
        (x: (f.gridX + need).clamp(host.gridX, host.gridX + host.width - f.width), y: f.gridY),
        (x: (f.gridX - need).clamp(host.gridX, host.gridX + host.width - f.width), y: f.gridY),
        (x: (host.gridX + host.width - f.width).clamp(host.gridX, cols - f.width), y: f.gridY),
        (x: host.gridX, y: f.gridY),
      ];
      for (final t in tries) {
        final trial = f.copyWith(gridX: t.x, gridY: t.y);
        if (LayoutCollision.itemCollides(trial, next)) continue;
        if (PlacementCatalog.pcVentilationBlockRatio(trial, next, cols, rows) < blocked) {
          next[i] = trial;
          break;
        }
      }
    }
    return next;
  }

  static List<FurnitureItem> _pushForbiddenOffWall(
    List<FurnitureItem> items,
    int cols,
    int rows,
  ) {
    final next = items.map((f) => f.copyWith()).toList();
    for (var i = 0; i < next.length; i++) {
      final f = next[i];
      if (f.locked) continue;
      final spec = PlacementCatalog.of(f);
      if (spec.wall != WallRequirement.forbidden) continue;
      if (!ItemPlacementRules.hay(f).contains('chair')) continue;
      if (f.gridX > wallTol &&
          f.gridY > wallTol &&
          cols - (f.gridX + f.width) > wallTol &&
          rows - (f.gridY + f.height) > wallTol) {
        continue;
      }
      // Chair re-seat owned by relinkPairedLayout.
    }
    return next;
  }

  static FurnitureItem? _findByKind(List<FurnitureItem> items, String kind) {
    for (final f in items) {
      if (PlacementCatalog.of(f).id == kind) return f;
      if (ItemPlacementRules.hay(f).contains(kind)) return f;
    }
    return null;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
