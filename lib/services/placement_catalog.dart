// Constraint catalog for Auto-Rig — sorting.md + sorting_response.md.
// Data-driven spatial rules. Not a score model.
import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'item_placement_rules.dart';
import 'layout_collision.dart';

/// Where the object lives in the room stack.
enum PlacementSurface { floor, wall, ceiling, onFurniture, underFurniture }

/// Wall contact strength — not a boolean.
enum WallRequirement {
  /// Door, window, wall AC, vents, blinds, wall-mounted TV.
  must,

  /// Bed headboard, wardrobe, shelf, desk, sofa, portable AC near wall.
  preferred,

  /// Plant, floor lamp — wall/corner OK but not required.
  allowed,

  /// Chair / open-floor climate — stay off the wall.
  forbidden,
}

/// Relational facing target (angle computed after targets exist).
enum FaceTarget {
  none,
  room,
  desk,
  chair,
  sofa,
  tv,
  window,
  airflowTarget,
  down,
}

/// How yaw should be derived (sorting_response OrientationMode).
enum OrientationMode {
  free,
  faceTarget,
  parallelToWall,
  perpendicularToWall,
  sameAsParent,
  down,
}

/// Relative pose vs a related object (not only parent-child).
enum RelativePlacement {
  none,
  leftOf,
  rightOf,
  beside,
  centerOf,
  inFrontOf,
  behind,
  above,
  below,
  under,
  near,
  mountedTo,
}

/// Placement priority class (solve in order A → E).
/// E = physically attached/dependent only — not every spatial association.
enum PlacementClass {
  /// Room anchors: door, window, HVAC, ceiling light.
  aAnchor,

  /// Major furniture: bed, desk, sofa, storage, TV, table, PC.
  bMajor,

  /// Functional peripherals: chair, monitor, lamps, plant, floor lamp.
  cPeripheral,

  /// Environmental modifiers after furniture (fans, heaters, purifier).
  dClimate,

  /// Physically attached upgrades — children only, never free-placed.
  eAttached,
}

/// One row of the constraint table.
class PlacementSpec {
  final String id;
  final PlacementSurface surface;
  final WallRequirement wall;
  final FaceTarget facing;
  final OrientationMode orientation;
  final PlacementClass klass;

  /// True mount: Monitor Arm → Desk, Blinds → Window.
  final String? physicalParent;

  /// Arrangement membership without a bolt: Monitor/PC/Lamp → Desk.
  final String? spatialParent;

  /// Functional pair: Chair ↔ Desk, Sofa ↔ TV, Portable AC ↔ Window.
  final String? functionalTarget;

  final RelativePlacement relative;
  final double frontClearance;
  final double backClearance;
  final double sideClearance;
  final double ventClearance;
  final bool participatesInMainLayout;

  const PlacementSpec({
    required this.id,
    required this.surface,
    required this.wall,
    required this.facing,
    required this.klass,
    this.orientation = OrientationMode.faceTarget,
    this.physicalParent,
    this.spatialParent,
    this.functionalTarget,
    this.relative = RelativePlacement.none,
    this.frontClearance = 0,
    this.backClearance = 0,
    this.sideClearance = 0,
    this.ventClearance = 0,
    this.participatesInMainLayout = true,
  });

  /// Legacy name used by older call sites — physical attachment only.
  String? get parentKind => physicalParent;

  /// Soft pairing hint (functional first, else spatial).
  String? get mainRelation => functionalTarget ?? spatialParent;

  bool get isPhysicalChild =>
      physicalParent != null && klass == PlacementClass.eAttached;

  bool get isChild => isPhysicalChild;

  bool get mustWall => wall == WallRequirement.must;

  bool get preferWall =>
      wall == WallRequirement.must || wall == WallRequirement.preferred;
}

/// Source of truth for catalog + upgrade spatial constraints.
class PlacementCatalog {
  PlacementCatalog._();

  /// CamelCase / legacy icon ids → canonical catalog id.
  static const Map<String, String> aliases = {
    'lightBar': 'upg_light_bar',
    'monitorArm': 'upg_monitor_arm',
    'cableTray': 'upg_cable_tray',
    'mat': 'upg_mat',
    'smartBlinds': 'upg_blinds',
    'blinds': 'upg_blinds',
    'purifier': 'upg_purifier',
    'floorLamp': 'floor_lamp',
    'ceilingLight': 'ceiling_light',
    'heater': 'space_heater',
  };

  static String canonicalize(String raw) {
    final k = raw.trim();
    return aliases[k] ?? aliases[k.toLowerCase()] ?? k;
  }

  static const Map<String, PlacementSpec> byId = {
    // —— Work ——
    'desk': PlacementSpec(
      id: 'desk',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.bMajor,
      functionalTarget: 'chair',
    ),
    'chair': PlacementSpec(
      id: 'chair',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.desk,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.cPeripheral,
      // Functional relationship — NOT a physical child of the desk.
      spatialParent: 'desk',
      functionalTarget: 'desk',
      relative: RelativePlacement.inFrontOf,
      frontClearance: 0.4,
      backClearance: 0.95,
      sideClearance: 0.35,
    ),
    'monitor': PlacementSpec(
      id: 'monitor',
      surface: PlacementSurface.onFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.chair,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.cPeripheral,
      spatialParent: 'desk',
      functionalTarget: 'chair',
      relative: RelativePlacement.centerOf,
      participatesInMainLayout: false,
    ),
    // System unit: on desk, beside monitor — Class B, not E attachment.
    'pc': PlacementSpec(
      id: 'pc',
      surface: PlacementSurface.onFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.none,
      orientation: OrientationMode.sameAsParent,
      klass: PlacementClass.bMajor,
      spatialParent: 'desk',
      functionalTarget: 'desk',
      relative: RelativePlacement.beside,
      ventClearance: 0.35,
      sideClearance: 0.25,
      participatesInMainLayout: false,
    ),
    'lamp': PlacementSpec(
      id: 'lamp',
      surface: PlacementSurface.onFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.desk,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.cPeripheral,
      spatialParent: 'desk',
      relative: RelativePlacement.beside,
      participatesInMainLayout: false,
    ),
    // —— Sleep / lounge ——
    'bed': PlacementSpec(
      id: 'bed',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.bMajor,
      functionalTarget: 'door',
      frontClearance: 0.6,
      sideClearance: 0.45,
    ),
    'sofa': PlacementSpec(
      id: 'sofa',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.tv,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.bMajor,
      functionalTarget: 'tv',
      frontClearance: 0.7,
    ),
    'table': PlacementSpec(
      id: 'table',
      surface: PlacementSurface.floor,
      wall: WallRequirement.allowed,
      facing: FaceTarget.none,
      orientation: OrientationMode.free,
      klass: PlacementClass.bMajor,
      functionalTarget: 'sofa',
      relative: RelativePlacement.near,
    ),
    // Wall-mounted TV defaults to must-wall; stand mode can relax later.
    'tv': PlacementSpec(
      id: 'tv',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.sofa,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.bMajor,
      functionalTarget: 'sofa',
    ),
    // —— Storage ——
    'wardrobe': PlacementSpec(
      id: 'wardrobe',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.room,
      orientation: OrientationMode.parallelToWall,
      klass: PlacementClass.bMajor,
      frontClearance: 1.1,
      sideClearance: 0.3,
    ),
    'shelf': PlacementSpec(
      id: 'shelf',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.room,
      orientation: OrientationMode.parallelToWall,
      klass: PlacementClass.bMajor,
      frontClearance: 0.55,
    ),
    // —— Openings / HVAC (anchors) ——
    'door': PlacementSpec(
      id: 'door',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.aAnchor,
      frontClearance: 1.2,
      participatesInMainLayout: false,
    ),
    'window': PlacementSpec(
      id: 'window',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.aAnchor,
      participatesInMainLayout: false,
    ),
    'ac': PlacementSpec(
      id: 'ac',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.aAnchor,
      frontClearance: 0.55,
      participatesInMainLayout: false,
    ),
    'intake': PlacementSpec(
      id: 'intake',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.aAnchor,
      frontClearance: 0.55,
      participatesInMainLayout: false,
    ),
    'exhaust': PlacementSpec(
      id: 'exhaust',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.room,
      orientation: OrientationMode.perpendicularToWall,
      klass: PlacementClass.aAnchor,
      frontClearance: 0.55,
      participatesInMainLayout: false,
    ),
    // —— Open-floor climate ——
    'portable_ac': PlacementSpec(
      id: 'portable_ac',
      surface: PlacementSurface.floor,
      wall: WallRequirement.preferred,
      facing: FaceTarget.room,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.dClimate,
      functionalTarget: 'window',
      relative: RelativePlacement.near,
      frontClearance: 0.5,
      sideClearance: 0.35,
    ),
    'fan': PlacementSpec(
      id: 'fan',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.airflowTarget,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.dClimate,
      functionalTarget: 'chair',
      frontClearance: 0.4,
    ),
    'space_heater': PlacementSpec(
      id: 'space_heater',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.room,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.dClimate,
      frontClearance: 0.6,
      sideClearance: 0.5,
      backClearance: 0.4,
    ),
    // —— Light / accent ——
    'floor_lamp': PlacementSpec(
      id: 'floor_lamp',
      surface: PlacementSurface.floor,
      wall: WallRequirement.allowed,
      facing: FaceTarget.room,
      orientation: OrientationMode.free,
      klass: PlacementClass.cPeripheral,
      relative: RelativePlacement.near,
    ),
    'ceiling_light': PlacementSpec(
      id: 'ceiling_light',
      surface: PlacementSurface.ceiling,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.down,
      orientation: OrientationMode.down,
      klass: PlacementClass.aAnchor,
    ),
    'plant': PlacementSpec(
      id: 'plant',
      surface: PlacementSurface.floor,
      wall: WallRequirement.allowed,
      facing: FaceTarget.none,
      orientation: OrientationMode.free,
      klass: PlacementClass.cPeripheral,
    ),
    // —— Upgrades: class by layout behavior, not "optional SKU" ——
    'upg_fan': PlacementSpec(
      id: 'upg_fan',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.airflowTarget,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.dClimate,
      functionalTarget: 'sofa',
    ),
    'upg_purifier': PlacementSpec(
      id: 'upg_purifier',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.none,
      orientation: OrientationMode.free,
      klass: PlacementClass.dClimate,
    ),
    'upg_light_bar': PlacementSpec(
      id: 'upg_light_bar',
      surface: PlacementSurface.onFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.desk,
      orientation: OrientationMode.sameAsParent,
      klass: PlacementClass.eAttached,
      physicalParent: 'desk',
      relative: RelativePlacement.mountedTo,
      participatesInMainLayout: false,
    ),
    'upg_floor_lamp': PlacementSpec(
      id: 'upg_floor_lamp',
      surface: PlacementSurface.floor,
      wall: WallRequirement.allowed,
      facing: FaceTarget.none,
      orientation: OrientationMode.free,
      klass: PlacementClass.cPeripheral,
    ),
    'upg_monitor_arm': PlacementSpec(
      id: 'upg_monitor_arm',
      surface: PlacementSurface.onFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.chair,
      orientation: OrientationMode.faceTarget,
      klass: PlacementClass.eAttached,
      physicalParent: 'desk',
      relative: RelativePlacement.mountedTo,
      participatesInMainLayout: false,
    ),
    'upg_cable_tray': PlacementSpec(
      id: 'upg_cable_tray',
      surface: PlacementSurface.underFurniture,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.desk,
      orientation: OrientationMode.sameAsParent,
      klass: PlacementClass.eAttached,
      physicalParent: 'desk',
      relative: RelativePlacement.under,
      participatesInMainLayout: false,
    ),
    'upg_mat': PlacementSpec(
      id: 'upg_mat',
      surface: PlacementSurface.floor,
      wall: WallRequirement.forbidden,
      facing: FaceTarget.desk,
      orientation: OrientationMode.free,
      klass: PlacementClass.eAttached,
      physicalParent: 'desk',
      relative: RelativePlacement.under,
      participatesInMainLayout: false,
    ),
    'upg_blinds': PlacementSpec(
      id: 'upg_blinds',
      surface: PlacementSurface.wall,
      wall: WallRequirement.must,
      facing: FaceTarget.window,
      orientation: OrientationMode.sameAsParent,
      klass: PlacementClass.eAttached,
      physicalParent: 'window',
      relative: RelativePlacement.mountedTo,
      participatesInMainLayout: false,
    ),
  };

  /// Resolve spec from furniture id / icon / name (aliases collapse duplicates).
  static PlacementSpec of(FurnitureItem f) {
    final hay = ItemPlacementRules.hay(f);

    // Icon / alias before bare id — preset "lamp" + icon floorLamp must not
    // resolve to the desk task-lamp row.
    PlacementSpec? fromKey(String raw) {
      if (raw.isEmpty) return null;
      final canon = canonicalize(raw);
      return byId[canon] ?? byId[raw] ?? byId[raw.toLowerCase()];
    }

    for (final key in [f.iconName, canonicalize(f.iconName), f.id, canonicalize(f.id)]) {
      final hit = fromKey(key);
      if (hit != null) return hit;
    }

    // Longer catalog keys first so "floor_lamp" / "portable_ac" beat "lamp" / "ac".
    final keys = byId.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (hay.contains(key.toLowerCase())) return byId[key]!;
    }
    for (final e in aliases.entries) {
      if (hay.contains(e.key.toLowerCase()) || hay.contains(e.value.toLowerCase())) {
        return byId[e.value]!;
      }
    }
    if (SurfaceMounts.isDoor(f)) return byId['door']!;
    if (SurfaceMounts.isWindow(f)) return byId['window']!;
    if (SurfaceMounts.isVent(f) || SurfaceMounts.isIntake(f)) return byId['intake']!;
    if (SurfaceMounts.isExhaust(f)) return byId['exhaust']!;
    if (SurfaceMounts.isDeskTopItem(f)) {
      return const PlacementSpec(
        id: 'desktop',
        surface: PlacementSurface.onFurniture,
        wall: WallRequirement.forbidden,
        facing: FaceTarget.chair,
        klass: PlacementClass.cPeripheral,
        spatialParent: 'desk',
        participatesInMainLayout: false,
      );
    }
    return const PlacementSpec(
      id: 'unknown',
      surface: PlacementSurface.floor,
      wall: WallRequirement.allowed,
      facing: FaceTarget.none,
      klass: PlacementClass.cPeripheral,
    );
  }

  static int hierarchyRank(PlacementClass c) {
    switch (c) {
      case PlacementClass.aAnchor:
        return 0;
      case PlacementClass.bMajor:
        return 1;
      case PlacementClass.cPeripheral:
        return 2;
      case PlacementClass.dClimate:
        return 3;
      case PlacementClass.eAttached:
        return 4;
    }
  }

  /// Sort for hierarchical placement (anchors → majors → … → attached).
  static List<FurnitureItem> sortForPlacement(List<FurnitureItem> items) {
    final copy = [...items];
    copy.sort((a, b) {
      final ra = hierarchyRank(of(a).klass);
      final rb = hierarchyRank(of(b).klass);
      if (ra != rb) return ra.compareTo(rb);
      return a.id.compareTo(b.id);
    });
    return copy;
  }

  /// True when conflict resolution must not move this piece.
  static bool isImmovableInConflicts(FurnitureItem f) {
    final s = of(f);
    if (s.klass == PlacementClass.aAnchor) return true;
    if (s.klass == PlacementClass.eAttached) return true;
    if (!s.participatesInMainLayout && s.klass != PlacementClass.bMajor) {
      // Desk-tops like monitor/lamp stay with host; PC may still nudge for vent.
      return true;
    }
    if (SurfaceMounts.isStructuralMount(f)) return true;
    return false;
  }

  /// Soft airflow penalty when PC vent sides are jammed (0 = clear, 1 = blocked).
  static double pcVentilationBlockRatio(FurnitureItem pc, List<FurnitureItem> others, int cols, int rows) {
    final spec = of(pc);
    if (spec.id != 'pc' || spec.ventClearance <= 0) return 0;
    final need = spec.ventClearance;
    var blocked = 0.0;
    // Left / right side pads.
    for (final side in ['l', 'r']) {
      final probe = pc.copyWith(
        gridX: side == 'l' ? pc.gridX - need : pc.gridX + pc.width,
        width: need,
      );
      final againstWall = side == 'l'
          ? pc.gridX <= 0.05
          : (cols - (pc.gridX + pc.width)) <= 0.05;
      if (againstWall) {
        blocked += 1;
        continue;
      }
      for (final o in others) {
        if (o.id == pc.id) continue;
        if (LayoutCollision.overlaps(probe, o)) {
          blocked += 1;
          break;
        }
      }
    }
    return (blocked / 2).clamp(0.0, 1.0);
  }
}
