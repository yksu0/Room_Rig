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
    // Spot-check the items that previously drifted (monitor / PC / fan / desk).
    expect(GltfCatalog.orbitFootprint('monitor').width, closeTo(1.25, 0.01));
    expect(GltfCatalog.orbitFootprint('monitor').depth, closeTo(0.35, 0.05));
    expect(GltfCatalog.orbitFootprint('pc').width, closeTo(0.35, 0.05));
    expect(GltfCatalog.orbitFootprint('pc').depth, closeTo(0.75, 0.05));
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
