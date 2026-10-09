import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/gltf_catalog.dart';
import 'package:room_rig/widgets/furniture_shapes.dart';

void main() {
  test('every catalog item declares metre fit metadata', () {
    expect(GltfCatalog.catalogKeys, isNotEmpty);
    for (final key in GltfCatalog.catalogKeys) {
      final p = GltfCatalog.profileFor(key);
      final fit = p.fitPayload();
      expect(fit['fit'], isNotEmpty, reason: '$key missing fit mode');
      expect(p.heightMeters, greaterThan(0), reason: '$key height');
      expect(fit['th'], p.heightMeters);
      expect(fit.containsKey('yawBias'), isTrue);
      expect(fit.containsKey('alignFoot'), isTrue);
      expect(fit['role'], p.role.name);
      if (p.role == MeshSimRole.emitter) {
        expect(fit['emit'], isTrue, reason: '$key emitter should flag emit');
      }
      if (p.fitMode == MeshFitMode.wallOpening) {
        expect(
          p.clearWidthMeters ?? p.targetWidthMeters,
          isNotNull,
          reason: '$key wallOpening needs clear/target width',
        );
      }
    }
  });

  test('Kenney desk bias +180; screens use yaw 0 (no extra flip)', () {
    expect(GltfCatalog.profileFor('desk').localYawBiasDegrees, 180);
    expect(GltfCatalog.profileFor('monitor').localYawBiasDegrees, 0);
    expect(GltfCatalog.profileFor('tv').localYawBiasDegrees, 0);
  });

  test('Orbit meshHeight matches MeshProfile for every catalog kind', () {
    const kinds = FurnitureKind.values;
    for (final kind in kinds) {
      if (kind == FurnitureKind.generic) continue;
      final icon = FurnitureShapes.catalogIconFor(kind);
      expect(
        FurnitureShapes.meshHeight(kind),
        GltfCatalog.profileFor(icon).heightMeters,
        reason: '$kind / $icon',
      );
    }
    expect(FurnitureShapes.deskTopY, GltfCatalog.profileFor('desk').heightMeters);
  });

  test('Orbit footprints match metre targets for every catalog icon', () {
    expect(GltfCatalog.orbitFootprint('fan').width, closeTo(0.55, 0.05));
    expect(GltfCatalog.orbitFootprint('desk').width, closeTo(2.0, 0.01));
    expect(GltfCatalog.orbitFootprint('desk').depth, closeTo(1.0, 0.01));

    for (final key in GltfCatalog.catalogKeys) {
      final p = GltfCatalog.profileFor(key);
      final fp = GltfCatalog.orbitFootprint(key);
      final wCells = p.footprintWidthCells;
      final dCells = p.footprintDepthCells;
      if (wCells != null) {
        expect(fp.width, closeTo(wCells, 0.001), reason: '$key width cells');
      }
      if (dCells != null) {
        expect(fp.depth, closeTo(dCells, 0.001), reason: '$key depth cells');
      }
      expect(fp.width, greaterThan(0), reason: '$key width');
      expect(fp.depth, greaterThan(0), reason: '$key depth');
    }
  });

  test('desk-top trio (PC + monitor + lamp) fills a standard desk width', () {
    final desk = GltfCatalog.orbitFootprint('desk');
    final pc = GltfCatalog.orbitFootprint('pc');
    final mon = GltfCatalog.orbitFootprint('monitor');
    final lamp = GltfCatalog.orbitFootprint('lamp');
    final trio = pc.width + mon.width + lamp.width;
    expect(trio, closeTo(desk.width, 0.1), reason: '2–3 desk items should fill the top');
    expect(pc.depth, lessThanOrEqualTo(desk.depth + 0.05));
    expect(mon.depth, lessThanOrEqualTo(desk.depth + 0.05));
    expect(lamp.depth, lessThanOrEqualTo(desk.depth + 0.05));
    // Uniform fit so Model meshes stay inside Orbit cells (no GLB overflow).
    for (final key in ['monitor', 'pc', 'lamp']) {
      expect(GltfCatalog.profileFor(key).fitMode, MeshFitMode.uniform);
    }
  });

  test('gaming preset packs desk-top gear without overlap', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final desk = room.furniture.firstWhere((f) => f.id == 'desk');
    final tops = room.furniture
        .where((f) => f.id == 'pc' || f.id == 'monitor' || f.id == 'lamp')
        .toList();
    expect(tops, hasLength(3));
    for (final a in tops) {
      expect(a.gridX, greaterThanOrEqualTo(desk.gridX - 0.01));
      expect(a.gridX + a.width, lessThanOrEqualTo(desk.gridX + desk.width + 0.05));
      expect(a.gridY, greaterThanOrEqualTo(desk.gridY - 0.01));
      expect(a.gridY + a.height, lessThanOrEqualTo(desk.gridY + desk.height + 0.05));
      for (final b in tops) {
        if (identical(a, b)) continue;
        final ax1 = a.gridX + a.width;
        final ay1 = a.gridY + a.height;
        final bx1 = b.gridX + b.width;
        final by1 = b.gridY + b.height;
        final overlap = a.gridX < bx1 && ax1 > b.gridX && a.gridY < by1 && ay1 > b.gridY;
        expect(overlap, isFalse, reason: '${a.id} vs ${b.id}');
      }
    }
  });

  test('Rig catalog footprints match orbitFootprint for every entry', () {
    for (final e in RigCatalog.items) {
      final fp = GltfCatalog.orbitFootprint(e.iconName);
      expect(e.width, closeTo(fp.width, 0.001), reason: '${e.baseId} width');
      expect(e.height, closeTo(fp.depth, 0.001), reason: '${e.baseId} depth');
    }
  });

  test('Room presets use catalog orbit footprints for every item', () {
    for (final room in RoomPresets.all) {
      for (final f in room.furniture) {
        final fp = GltfCatalog.orbitFootprint(f.iconName);
        expect(
          f.width,
          closeTo(fp.width, 0.001),
          reason: '${room.name} ${f.id} width',
        );
        expect(
          f.height,
          closeTo(fp.depth, 0.001),
          reason: '${room.name} ${f.id} depth',
        );
      }
    }
  });
}
