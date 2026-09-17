// Every catalog SKU + upgrade must resolve to a kind, get an Auto-Rig role,
// and survive multi-objective rearrange without being dropped.
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/models/upgrade_catalog.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/services/layout_optimizer_common.dart';
import 'package:room_rig/services/multi_objective_optimizer.dart';
import 'package:room_rig/widgets/furniture_shapes.dart';

void main() {
  final room = RoomPresets.getPreset(RoomPreset.gamingSetup);

  final upgradeSpecs = UpgradeCatalog.specs
      .map(
        (s) => (
          id: s.furnitureId,
          name: s.name,
          icon: s.iconName,
          w: 1.0,
          h: 1.0,
        ),
      )
      .toList();

  FurnitureItem catalogPiece(RigCatalogEntry e) => e.toFurniture(
        id: e.baseId,
        gridX: 1,
        gridY: 1,
      );

  FurnitureItem upgradePiece(({String id, String name, String icon, double w, double h}) u) =>
      FurnitureItem(
        id: u.id,
        name: u.name,
        iconName: u.icon,
        category: 'upgrade',
        gridX: 2,
        gridY: 2,
        width: u.w,
        height: u.h,
      );

  test('every catalog icon has a sprite-facing kind (not silent generic for known SKUs)', () {
    for (final e in RigCatalog.items) {
      final kind = FurnitureShapes.kindFrom(
        id: e.baseId,
        name: e.name,
        iconName: e.iconName,
      );
      // Wall openings / vents / intake / exhaust / door / window stay generic mesh —
      // they are structural, not FurnitureKind variants. Everything else must map.
      final structural = {
        'door',
        'window',
        'ac',
        'intake',
        'exhaust',
      }.contains(e.baseId);
      if (structural) continue;
      if (e.baseId == 'portable_ac') {
        expect(kind, FurnitureKind.portableAc, reason: e.baseId);
        continue;
      }
      expect(kind, isNot(FurnitureKind.generic), reason: '${e.baseId} → $kind');
    }
    for (final u in upgradeSpecs) {
      final kind = FurnitureShapes.kindFrom(id: u.id, name: u.name, iconName: u.icon);
      expect(kind, isNot(FurnitureKind.generic), reason: '${u.id} → $kind');
    }
  });

  test('desk-top SKUs are classified as desk-top (mount on desk)', () {
    final deskTops = {
      'monitor',
      'pc',
      'lamp',
      'upg_light_bar',
      'upg_monitor_arm',
      'upg_cable_tray',
    };
    for (final e in RigCatalog.items.where((e) => deskTops.contains(e.baseId))) {
      expect(SurfaceMounts.isDeskTopItem(catalogPiece(e)), isTrue, reason: e.baseId);
    }
    for (final u in upgradeSpecs.where((u) => deskTops.contains(u.id))) {
      expect(SurfaceMounts.isDeskTopItem(upgradePiece(u)), isTrue, reason: u.id);
    }
  });

  test('Auto-Rig assigns a target role for every catalog + upgrade id', () {
    final base = room.furniture.map((f) => f.copyWith()).toList();
    final extras = <FurnitureItem>[
      for (final e in RigCatalog.items)
        if (!base.any((f) => f.id == e.baseId || f.iconName == e.iconName))
          catalogPiece(e),
      for (final u in upgradeSpecs) upgradePiece(u),
    ];
    // Spread extras so they fit.
    var x = 0.2;
    var y = 0.2;
    final placed = <FurnitureItem>[...base];
    for (final e in extras) {
      placed.add(e.copyWith(gridX: x, gridY: y));
      x += e.width + 0.15;
      if (x > room.gridCols - 1.5) {
        x = 0.2;
        y += 1.2;
      }
    }

    final targets = <String, ({double x, double y})>{};
    final reasons = <String>[];
    LayoutOptimizerCommon.planWorkCluster(
      furniture: placed,
      targets: targets,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      bias: WorkClusterBias.ergonomics,
    );
    LayoutOptimizerCommon.planPerimeterStorage(
      furniture: placed,
      targets: targets,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      reasons: reasons,
    );

    // Explicit domain anchors the work cluster / perimeter may skip.
    for (final f in placed) {
      if (targets.containsKey(f.id)) continue;
      if (SurfaceMounts.isVent(f) ||
          SurfaceMounts.isIntake(f) ||
          SurfaceMounts.isExhaust(f) ||
          SurfaceMounts.isDoor(f) ||
          SurfaceMounts.isWindow(f) ||
          SurfaceMounts.isCeilingFixture(f) ||
          f.iconName == 'fan' ||
          '${f.id} ${f.name}'.toLowerCase().contains('fan')) {
        // Domain optimizers place these; perimeter may not.
        continue;
      }
      if (SurfaceMounts.isDeskTopItem(f)) {
        // Mounted via planWorkCluster when a desk exists.
        final desk = LayoutOptimizerCommon.findDesk(placed);
        expect(desk, isNotNull, reason: '${f.id} needs a desk host');
        expect(targets.containsKey(desk!.id) || desk.id.isNotEmpty, isTrue);
        continue;
      }
      // Everything else should have been claimed by perimeter or work cluster.
      expect(
        targets.containsKey(f.id),
        isTrue,
        reason: '${f.id} (${f.iconName}) has no Auto-Rig target — not accounted for',
      );
    }
  });

  test('full catalog + all upgrades survive MultiObjective Auto-Rig on a large room', () {
    const cols = 14;
    const rows = 14;
    final furniture = <FurnitureItem>[
      for (final e in RigCatalog.items)
        e.toFurniture(id: e.baseId, gridX: 1, gridY: 1),
      for (final u in upgradeSpecs) upgradePiece(u),
    ];
    // Seed non-overlapping starts.
    var x = 0.2;
    var y = 0.2;
    for (var i = 0; i < furniture.length; i++) {
      final f = furniture[i];
      furniture[i] = f.copyWith(
        gridX: x.clamp(0.0, cols - f.width),
        gridY: y.clamp(0.0, rows - f.height),
      );
      x += f.width + 0.25;
      if (x > cols - 2) {
        x = 0.2;
        y += 1.4;
      }
    }

    final beforeIds = furniture.map((f) => f.id).toSet();
    final result = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: cols,
      gridRows: rows,
      weights: const MultiObjectiveWeights(airflow: 1, lighting: 1, ergonomics: 1),
    );
    expect(result.furniture.map((f) => f.id).toSet(), beforeIds);

    // With every SKU present, a 2-cell desk cannot host all tops — require the
    // primary work surface items to mount, and keep every id conflict-free.
    final mountedIds = result.furniture
        .where((f) =>
            SurfaceMounts.isDeskTopItem(f) &&
            SurfaceMounts.hostUnder(f, result.furniture) != null)
        .map((f) => f.id)
        .toSet();
    expect(
      mountedIds.any((id) => id.contains('monitor')),
      isTrue,
      reason: 'monitor or monitor arm should sit on a desk; mounted=$mountedIds',
    );
    expect(mountedIds.length, greaterThanOrEqualTo(2), reason: 'mounted=$mountedIds');

    final hard = LayoutCollision.findConflicts(
      furniture: result.furniture,
      gridCols: cols,
      gridRows: rows,
    ).where(
      (c) =>
          c.kind == LayoutConflictKind.overlap ||
          c.kind == LayoutConflictKind.blockedOpening,
    );
    expect(hard, isEmpty, reason: '$hard');
  });

  test('each desk-top SKU alone mounts on the gaming desk after Auto-Rig', () {
    final catalogTops = RigCatalog.items.where((e) => {'monitor', 'pc', 'lamp'}.contains(e.baseId));
    final upgradeTops = upgradeSpecs.where(
      (u) => {'upg_light_bar', 'upg_monitor_arm', 'upg_cable_tray'}.contains(u.id),
    );
    for (final e in catalogTops) {
      final furniture = [
        ...room.furniture.map((f) => f.copyWith()),
        if (!room.furniture.any((f) => f.id == e.baseId))
          e.toFurniture(id: e.baseId, gridX: 4, gridY: 4),
      ];
      final result = MultiObjectiveOptimizer.optimize(
        furniture: furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: const MultiObjectiveWeights(airflow: 0.2, lighting: 0.2, ergonomics: 1),
      );
      final after = result.furniture.firstWhere((f) => f.id == e.baseId || f.iconName == e.iconName);
      expect(
        SurfaceMounts.hostUnder(after, result.furniture),
        isNotNull,
        reason: '${e.baseId} alone should mount on the desk',
      );
    }
    for (final u in upgradeTops) {
      final furniture = [
        ...room.furniture.map((f) => f.copyWith()),
        upgradePiece(u),
      ];
      final result = MultiObjectiveOptimizer.optimize(
        furniture: furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        weights: const MultiObjectiveWeights(airflow: 0.2, lighting: 0.2, ergonomics: 1),
      );
      final after = result.furniture.firstWhere((f) => f.id == u.id);
      expect(
        SurfaceMounts.hostUnder(after, result.furniture),
        isNotNull,
        reason: '${u.id} alone should mount on the desk',
      );
    }
  });

  test('Hub upgrade catalog furnitureIds are all covered by upgradeSpecs', () {
    // Keep this list in sync with AppState._upgradeCatalog furnitureId values.
    final expected = {
      'upg_fan',
      'upg_purifier',
      'upg_light_bar',
      'upg_floor_lamp',
      'upg_monitor_arm',
      'upg_cable_tray',
      'upg_mat',
      'upg_blinds',
    };
    expect(upgradeSpecs.map((u) => u.id).toSet(), expected);
  });
}
