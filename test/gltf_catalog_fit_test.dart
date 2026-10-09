import 'package:flutter_test/flutter_test.dart';
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
}
