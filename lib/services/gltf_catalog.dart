// Maps Rig furniture icon names → Kenney CC0 GLB assets + sim mesh profiles.
// Source: Kenney Furniture Kit (CC0). Room textures: Poly Haven (CC0).
//
// Mesh profiles drive airflow collision volumes and lighting occluders so the
// Model view GLBs and Bench physics share one source of truth.

import '../models/room_model.dart';

/// Physical role of a mesh in airflow / lighting.
enum MeshSimRole {
  /// Solid furniture — blocks particles and casts hard shadows.
  solid,

  /// Heat / cold / fan emitters keep specialty boxes in the simulators.
  emitter,

  /// Door / window opening — not a solid; vents pressure / admits light.
  opening,

  /// Glass / translucent — particles pass; light is attenuated (refract approx).
  glass,

  /// Decorative / ignored by coarse sims.
  ignore,
}

class MeshProfile {
  final String iconName;
  final String? assetPath;
  final double heightMeters;
  final MeshSimRole role;

  /// 0 = opaque blocker, 1 = fully clear. Used by lighting ray march.
  final double lightTransmit;

  /// Soft particle collision factor (1 = full bounce, 0 = no hard collision).
  final double airflowSolid;

  const MeshProfile({
    required this.iconName,
    required this.assetPath,
    required this.heightMeters,
    required this.role,
    this.lightTransmit = 0,
    this.airflowSolid = 1,
  });

  bool get hasModel => assetPath != null;
  bool get isOpening => role == MeshSimRole.opening;
  bool get isGlass => role == MeshSimRole.glass;
  bool get castsHardShadow =>
      role == MeshSimRole.solid && lightTransmit < 0.15 && heightMeters >= 0.45;
}

class GltfCatalog {
  GltfCatalog._();

  static const kenneyDir = 'assets/gltf/kenney';

  static final Map<String, MeshProfile> _profiles = {
    'desk': const MeshProfile(
      iconName: 'desk',
      assetPath: '$kenneyDir/desk.glb',
      heightMeters: 0.75,
      role: MeshSimRole.solid,
    ),
    'table': const MeshProfile(
      iconName: 'table',
      assetPath: '$kenneyDir/tableCoffee.glb',
      heightMeters: 0.45,
      role: MeshSimRole.solid,
      airflowSolid: 0.85,
    ),
    'chair': const MeshProfile(
      iconName: 'chair',
      assetPath: '$kenneyDir/chairDesk.glb',
      heightMeters: 1.05,
      role: MeshSimRole.solid,
      airflowSolid: 0.7,
    ),
    'bed': const MeshProfile(
      iconName: 'bed',
      assetPath: '$kenneyDir/bedDouble.glb',
      heightMeters: 0.55,
      role: MeshSimRole.solid,
    ),
    'sofa': const MeshProfile(
      iconName: 'sofa',
      assetPath: '$kenneyDir/loungeSofa.glb',
      heightMeters: 0.85,
      role: MeshSimRole.solid,
    ),
    'shelf': const MeshProfile(
      iconName: 'shelf',
      assetPath: '$kenneyDir/bookcaseOpen.glb',
      heightMeters: 1.8,
      role: MeshSimRole.solid,
    ),
    'bookshelf': const MeshProfile(
      iconName: 'bookshelf',
      assetPath: '$kenneyDir/bookcaseClosed.glb',
      heightMeters: 1.85,
      role: MeshSimRole.solid,
    ),
    'wardrobe': const MeshProfile(
      iconName: 'wardrobe',
      assetPath: '$kenneyDir/cabinetBedDrawer.glb',
      heightMeters: 1.9,
      role: MeshSimRole.solid,
    ),
    'lamp': const MeshProfile(
      iconName: 'lamp',
      assetPath: '$kenneyDir/lampRoundTable.glb',
      heightMeters: 0.45,
      role: MeshSimRole.emitter,
      airflowSolid: 0.15,
      lightTransmit: 0.35,
    ),
    'floorLamp': const MeshProfile(
      iconName: 'floorLamp',
      assetPath: '$kenneyDir/lampSquareFloor.glb',
      heightMeters: 1.55,
      role: MeshSimRole.emitter,
      airflowSolid: 0.25,
      lightTransmit: 0.2,
    ),
    'ceilingLight': const MeshProfile(
      iconName: 'ceilingLight',
      assetPath: '$kenneyDir/lampSquareCeiling.glb',
      heightMeters: 0.12,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.5,
    ),
    'plant': const MeshProfile(
      iconName: 'plant',
      assetPath: '$kenneyDir/pottedPlant.glb',
      heightMeters: 0.7,
      role: MeshSimRole.solid,
      airflowSolid: 0.45,
      lightTransmit: 0.25,
    ),
    'monitor': const MeshProfile(
      iconName: 'monitor',
      assetPath: '$kenneyDir/computerScreen.glb',
      heightMeters: 0.5,
      role: MeshSimRole.solid,
      airflowSolid: 0.35,
    ),
    'tv': const MeshProfile(
      iconName: 'tv',
      assetPath: '$kenneyDir/televisionModern.glb',
      heightMeters: 0.55,
      role: MeshSimRole.solid,
      airflowSolid: 0.4,
    ),
    'pc': const MeshProfile(
      iconName: 'pc',
      assetPath: '$kenneyDir/speaker.glb',
      heightMeters: 0.5,
      role: MeshSimRole.emitter,
      airflowSolid: 0.9,
    ),
    'fan': const MeshProfile(
      iconName: 'fan',
      assetPath: '$kenneyDir/coatRackStanding.glb',
      heightMeters: 1.2,
      role: MeshSimRole.emitter,
      airflowSolid: 0.2,
    ),
    'purifier': const MeshProfile(
      iconName: 'purifier',
      assetPath: '$kenneyDir/speakerSmall.glb',
      heightMeters: 0.7,
      role: MeshSimRole.emitter,
      airflowSolid: 0.55,
    ),
    'heater': const MeshProfile(
      iconName: 'heater',
      assetPath: '$kenneyDir/kitchenCabinet.glb',
      heightMeters: 0.75,
      role: MeshSimRole.emitter,
    ),
    'ac': const MeshProfile(
      iconName: 'ac',
      assetPath: '$kenneyDir/hoodModern.glb',
      heightMeters: 0.35,
      role: MeshSimRole.emitter,
      airflowSolid: 0.3,
    ),
    'intake': const MeshProfile(
      iconName: 'intake',
      assetPath: '$kenneyDir/wall.glb',
      heightMeters: 0.35,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.4,
    ),
    'exhaust': const MeshProfile(
      iconName: 'exhaust',
      assetPath: '$kenneyDir/hoodModern.glb',
      heightMeters: 0.35,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.4,
    ),
    'door': const MeshProfile(
      iconName: 'door',
      assetPath: '$kenneyDir/doorwayOpen.glb',
      heightMeters: 2.1,
      role: MeshSimRole.opening,
      lightTransmit: 0.95,
      airflowSolid: 0,
    ),
    'window': const MeshProfile(
      iconName: 'window',
      assetPath: '$kenneyDir/wallWindow.glb',
      heightMeters: 1.2,
      role: MeshSimRole.glass,
      lightTransmit: 0.82,
      airflowSolid: 0,
    ),
    'smartBlinds': const MeshProfile(
      iconName: 'smartBlinds',
      assetPath: '$kenneyDir/wallWindowSlide.glb',
      heightMeters: 1.2,
      role: MeshSimRole.glass,
      lightTransmit: 0.35,
      airflowSolid: 0,
    ),
  };

  static MeshProfile profileFor(String iconName) {
    final key = iconName.trim();
    return _profiles[key] ??
        MeshProfile(
          iconName: key,
          assetPath: null,
          heightMeters: 0.9,
          role: MeshSimRole.solid,
        );
  }

  static MeshProfile profileForItem(FurnitureItem item) =>
      profileFor(item.iconName);

  /// Flutter asset path for a furniture [iconName], or null for placeholder.
  static String? assetForIcon(String iconName) => profileFor(iconName).assetPath;

  static double defaultHeightMeters(String iconName) =>
      profileFor(iconName).heightMeters;

  /// Relative URL from `assets/scene/room_viewer.html`.
  static String? sceneUrlForIcon(String iconName) {
    final asset = assetForIcon(iconName);
    if (asset == null) return null;
    return '../gltf/${asset.replaceFirst('assets/gltf/', '')}';
  }
}
