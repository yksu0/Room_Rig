// Maps Rig furniture icon names → CC0 GLB/glTF assets + sim / wall-cut profiles.
//
// Sources (see assets/gltf/SOURCES.md):
// - Kenney Furniture Kit — most furniture
// - Poly Haven — HVAC (aircon, ducts) when present under assets/gltf/hvac/
// - Quaternius / Poly Pizza — recommended for stand fans, purifiers (drop-in)

import '../models/room_model.dart';

/// Physical role of a mesh in airflow / lighting.
enum MeshSimRole {
  solid,
  emitter,
  opening,
  glass,
  ignore,
}

/// How a wall fitting cuts the room shell.
enum WallCutKind {
  /// No shell cut — model sits on the interior face.
  none,

  /// Full through-hole (door / window) — exterior visible.
  through,

  /// Recess filled with an opaque grille (AC / vents) — no outdoor view.
  niche,
}

class MeshProfile {
  final String iconName;
  final String? assetPath;
  final double heightMeters;
  final MeshSimRole role;
  final double lightTransmit;
  final double airflowSolid;

  /// Extra meters added around the wall cut so frames/louvers fit.
  final double wallCutPadMeters;

  final WallCutKind wallCut;

  const MeshProfile({
    required this.iconName,
    required this.assetPath,
    required this.heightMeters,
    required this.role,
    this.lightTransmit = 0,
    this.airflowSolid = 1,
    this.wallCutPadMeters = 0.04,
    this.wallCut = WallCutKind.none,
  });

  bool get hasModel => assetPath != null;
  bool get isOpening => role == MeshSimRole.opening;
  bool get isGlass => role == MeshSimRole.glass;
  bool get cutsWall => wallCut != WallCutKind.none;
}

class GltfCatalog {
  GltfCatalog._();

  static const kenneyDir = 'assets/gltf/kenney';
  static const hvacDir = 'assets/gltf/hvac';

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
    // CC0 HVAC pack under assets/gltf/hvac/ (see SOURCES.md).
    'fan': const MeshProfile(
      iconName: 'fan',
      assetPath: '$hvacDir/stand_fan.glb',
      heightMeters: 1.0,
      role: MeshSimRole.emitter,
      airflowSolid: 0.15,
    ),
    'purifier': const MeshProfile(
      iconName: 'purifier',
      assetPath: '$hvacDir/air_scrubber.glb',
      heightMeters: 1.05,
      role: MeshSimRole.emitter,
      airflowSolid: 0.55,
    ),
    'heater': const MeshProfile(
      iconName: 'heater',
      assetPath: '$hvacDir/radiator.glb',
      heightMeters: 0.68,
      role: MeshSimRole.emitter,
      airflowSolid: 0.7,
    ),
    'ac': const MeshProfile(
      iconName: 'ac',
      assetPath: '$hvacDir/ac_condenser.glb',
      heightMeters: 0.62,
      role: MeshSimRole.emitter,
      airflowSolid: 0.25,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.02,
    ),
    'intake': const MeshProfile(
      iconName: 'intake',
      assetPath: '$hvacDir/extract_fan_grille.glb',
      heightMeters: 0.32,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.12,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.015,
    ),
    'exhaust': const MeshProfile(
      iconName: 'exhaust',
      assetPath: '$hvacDir/extract_fan_grille.glb',
      heightMeters: 0.32,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.12,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.015,
    ),
    'door': const MeshProfile(
      iconName: 'door',
      assetPath: '$kenneyDir/doorwayOpen.glb',
      heightMeters: 2.1,
      role: MeshSimRole.opening,
      lightTransmit: 0.95,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      // Tight to the doorway leaf — avoid oversized sky holes.
      wallCutPadMeters: 0.015,
    ),
    'window': const MeshProfile(
      iconName: 'window',
      assetPath: '$kenneyDir/wallWindow.glb',
      heightMeters: 1.15,
      role: MeshSimRole.glass,
      lightTransmit: 0.82,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      wallCutPadMeters: 0.02,
    ),
    'smartBlinds': const MeshProfile(
      iconName: 'smartBlinds',
      assetPath: '$kenneyDir/wallWindowSlide.glb',
      heightMeters: 1.15,
      role: MeshSimRole.glass,
      lightTransmit: 0.35,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      wallCutPadMeters: 0.02,
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

  static String? assetForIcon(String iconName) => profileFor(iconName).assetPath;

  static double defaultHeightMeters(String iconName) =>
      profileFor(iconName).heightMeters;

  static String? sceneUrlForIcon(String iconName) {
    final asset = assetForIcon(iconName);
    if (asset == null) return null;
    return '../gltf/${asset.replaceFirst('assets/gltf/', '')}';
  }
}
