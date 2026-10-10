// Maps Rig furniture icon names → CC0 GLB/glTF assets + sim / wall-cut /
// Model-fit profiles.
//
// Sizing convention (one source of truth per kind):
// - [MeshFitMode] + optional targetWidth/Depth/Height metres drive the viewer.
// - Grid cells are for placement; fixed [targetWidthMeters] overrides footprint
//   when set (monitors, doors, etc.).
// - [localYawBiasDegrees] rotates Kenney fronts (-Z) to Orbit +Z = yaw 0.
// - Prefer changing targets here over magic scale multipliers in room_viewer.
//
// Sources (see assets/gltf/SOURCES.md):
// - Kenney Furniture Kit — most furniture
// - Poly Haven / HVAC pack — ac, fan, purifier, heater, vents

import '../models/room_model.dart';
import '../models/room_scale.dart';

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

/// How the Model viewer scales a GLB into its target box.
enum MeshFitMode {
  /// Uniform scale; stay inside W×D×H (default for most furniture).
  uniform,

  /// Uniform scale from width only (screens).
  width,

  /// Uniform scale from height only (towers, lamps, plants).
  height,

  /// Uniform scale from clear width × opening height; ignore wall thickness.
  wallOpening,
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

  /// Clear opening width along the wall (metres). Null → use furniture footprint.
  final double? clearWidthMeters;

  /// Clear opening height (metres). Null → use [heightMeters] / mount band.
  final double? clearHeightMeters;

  /// Model fit mode consumed by `room_viewer.html`.
  final MeshFitMode fitMode;

  /// Optional real-world width (m). Null → use grid footprint width.
  final double? targetWidthMeters;

  /// Optional real-world depth (m). Null → use grid footprint depth.
  final double? targetDepthMeters;

  /// Local Y rotation (degrees) so Kenney “front” matches Orbit yaw 0 = +Z.
  final double localYawBiasDegrees;

  /// Rotate 90° when mesh long-axis disagrees with the footprint.
  final bool alignFootprint;

  const MeshProfile({
    required this.iconName,
    required this.assetPath,
    required this.heightMeters,
    required this.role,
    this.lightTransmit = 0,
    this.airflowSolid = 1,
    this.wallCutPadMeters = 0.04,
    this.wallCut = WallCutKind.none,
    this.clearWidthMeters,
    this.clearHeightMeters,
    this.fitMode = MeshFitMode.uniform,
    this.targetWidthMeters,
    this.targetDepthMeters,
    this.localYawBiasDegrees = 0,
    this.alignFootprint = false,
  });

  bool get hasModel => assetPath != null;
  bool get isOpening => role == MeshSimRole.opening;
  bool get isGlass => role == MeshSimRole.glass;
  bool get cutsWall => wallCut != WallCutKind.none;

  double get openingHeightMeters => clearHeightMeters ?? heightMeters;

  /// Orbit / Rig grid width in cells from metre targets (0.05-cell snap).
  double? get footprintWidthCells {
    final m = clearWidthMeters ?? targetWidthMeters;
    if (m == null) return null;
    return GltfCatalog.cellsFromMeters(m);
  }

  /// Orbit / Rig grid depth in cells from metre targets (0.05-cell snap).
  double? get footprintDepthCells {
    final m = targetDepthMeters;
    if (m == null) return null;
    return GltfCatalog.cellsFromMeters(m);
  }

  /// Fit fields embedded in the Model scene JSON payload.
  Map<String, dynamic> fitPayload() => {
        'fit': fitMode.name,
        'th': heightMeters,
        'yawBias': localYawBiasDegrees,
        'alignFoot': alignFootprint,
        if (targetWidthMeters != null) 'tw': targetWidthMeters,
        if (targetDepthMeters != null) 'td': targetDepthMeters,
        'role': role.name,
        if (role == MeshSimRole.emitter) 'emit': true,
      };
}

class GltfCatalog {
  GltfCatalog._();

  static const kenneyDir = 'assets/gltf/kenney';
  static const hvacDir = 'assets/gltf/hvac';

  static final Map<String, MeshProfile> _profiles = {
    'desk': const MeshProfile(
      iconName: 'desk',
      assetPath: '$kenneyDir/desk.glb',
      heightMeters: 0.74,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 1.2,
      targetDepthMeters: 0.6,
      // Kenney drawer / knee opening faces -Z; Orbit chair sits on +Z.
      localYawBiasDegrees: 180,
      alignFootprint: true,
    ),
    'table': const MeshProfile(
      iconName: 'table',
      assetPath: '$kenneyDir/tableCoffee.glb',
      heightMeters: 0.45,
      role: MeshSimRole.solid,
      airflowSolid: 0.85,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 1.2,
      targetDepthMeters: 0.6,
      alignFootprint: true,
    ),
    'chair': const MeshProfile(
      iconName: 'chair',
      assetPath: '$kenneyDir/chairDesk.glb',
      heightMeters: 1.05,
      role: MeshSimRole.solid,
      airflowSolid: 0.7,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.65,
      targetDepthMeters: 0.65,
    ),
    'bed': const MeshProfile(
      iconName: 'bed',
      assetPath: '$kenneyDir/bedDouble.glb',
      heightMeters: 0.55,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 1.2,
      targetDepthMeters: 1.2,
      alignFootprint: true,
    ),
    'sofa': const MeshProfile(
      iconName: 'sofa',
      assetPath: '$kenneyDir/loungeSofa.glb',
      heightMeters: 0.85,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 1.2,
      targetDepthMeters: 0.6,
      alignFootprint: true,
    ),
    'shelf': const MeshProfile(
      iconName: 'shelf',
      assetPath: '$kenneyDir/bookcaseOpen.glb',
      heightMeters: 1.8,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.85,
      targetDepthMeters: 0.4,
      alignFootprint: true,
    ),
    'bookshelf': const MeshProfile(
      iconName: 'bookshelf',
      assetPath: '$kenneyDir/bookcaseClosed.glb',
      heightMeters: 1.85,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.85,
      targetDepthMeters: 0.4,
      alignFootprint: true,
    ),
    'wardrobe': const MeshProfile(
      iconName: 'wardrobe',
      assetPath: '$kenneyDir/cabinetBedDrawer.glb',
      heightMeters: 1.9,
      role: MeshSimRole.solid,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.9,
      targetDepthMeters: 0.55,
      alignFootprint: true,
    ),
    'lamp': const MeshProfile(
      iconName: 'lamp',
      assetPath: '$kenneyDir/lampRoundTable.glb',
      heightMeters: 0.42,
      role: MeshSimRole.emitter,
      airflowSolid: 0.15,
      lightTransmit: 0.35,
      // ~¼ of a 1.2 m desk — with monitor + PC, three fill the top.
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.30,
      targetDepthMeters: 0.35,
    ),
    'floorLamp': const MeshProfile(
      iconName: 'floorLamp',
      assetPath: '$kenneyDir/lampSquareFloor.glb',
      heightMeters: 1.55,
      role: MeshSimRole.emitter,
      airflowSolid: 0.25,
      lightTransmit: 0.2,
      fitMode: MeshFitMode.height,
      targetWidthMeters: 0.35,
      targetDepthMeters: 0.35,
    ),
    'ceilingLight': const MeshProfile(
      iconName: 'ceilingLight',
      assetPath: '$kenneyDir/lampSquareCeiling.glb',
      heightMeters: 0.12,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.5,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.35,
      targetDepthMeters: 0.35,
    ),
    'plant': const MeshProfile(
      iconName: 'plant',
      assetPath: '$kenneyDir/pottedPlant.glb',
      heightMeters: 0.7,
      role: MeshSimRole.solid,
      airflowSolid: 0.45,
      lightTransmit: 0.25,
      fitMode: MeshFitMode.height,
      targetWidthMeters: 0.4,
      targetDepthMeters: 0.4,
    ),
    'monitor': const MeshProfile(
      iconName: 'monitor',
      assetPath: '$kenneyDir/computerScreen.glb',
      heightMeters: 0.50,
      role: MeshSimRole.solid,
      airflowSolid: 0.35,
      // ~½ of a 1.2 m desk — uniform so Model never overshoots the Orbit cell.
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.55,
      targetDepthMeters: 0.42,
      // Kenney computerScreen already faces Orbit +Z (yaw 0 → chair).
      localYawBiasDegrees: 0,
    ),
    'tv': const MeshProfile(
      iconName: 'tv',
      assetPath: '$kenneyDir/televisionModern.glb',
      heightMeters: 0.65,
      role: MeshSimRole.solid,
      airflowSolid: 0.4,
      fitMode: MeshFitMode.width,
      targetWidthMeters: 1.1,
      targetDepthMeters: 0.28,
      localYawBiasDegrees: 0,
    ),
    'pc': const MeshProfile(
      iconName: 'pc',
      assetPath: '$kenneyDir/speaker.glb',
      heightMeters: 0.55,
      role: MeshSimRole.emitter,
      airflowSolid: 0.9,
      // ~⅓ of desk width; uniform keeps the tall GLB inside the Orbit footprint.
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.35,
      targetDepthMeters: 0.50,
    ),
    // CC0 HVAC pack under assets/gltf/hvac/ (see SOURCES.md).
    // Placeholder cage/blower GLB — not a household pedestal; keep modest until
    // a CC0 stand-fan drop-in lands (see assets/gltf/SOURCES.md).
    'fan': const MeshProfile(
      iconName: 'fan',
      assetPath: '$hvacDir/stand_fan.glb',
      heightMeters: 0.85,
      role: MeshSimRole.emitter,
      airflowSolid: 0.15,
      fitMode: MeshFitMode.height,
      targetWidthMeters: 0.32,
      targetDepthMeters: 0.32,
    ),
    'purifier': const MeshProfile(
      iconName: 'purifier',
      assetPath: '$hvacDir/air_scrubber.glb',
      heightMeters: 1.05,
      role: MeshSimRole.emitter,
      airflowSolid: 0.55,
      fitMode: MeshFitMode.height,
      targetWidthMeters: 0.4,
      targetDepthMeters: 0.4,
    ),
    'heater': const MeshProfile(
      iconName: 'heater',
      assetPath: '$hvacDir/radiator.glb',
      heightMeters: 0.68,
      role: MeshSimRole.emitter,
      airflowSolid: 0.7,
      fitMode: MeshFitMode.uniform,
      targetWidthMeters: 0.7,
      targetDepthMeters: 0.25,
    ),
    'ac': const MeshProfile(
      iconName: 'ac',
      assetPath: '$hvacDir/ac_condenser.glb',
      heightMeters: 0.62,
      role: MeshSimRole.emitter,
      airflowSolid: 0.25,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.02,
      clearWidthMeters: 0.9,
      clearHeightMeters: 0.62,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.9,
      targetDepthMeters: 0.14,
      // Kenney/HVAC wall meshes are often long on Z — rotate to local +X = along-wall.
      alignFootprint: true,
    ),
    'intake': const MeshProfile(
      iconName: 'intake',
      assetPath: '$hvacDir/extract_fan_grille.glb',
      heightMeters: 0.32,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.12,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.012,
      clearWidthMeters: 0.45,
      clearHeightMeters: 0.32,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.45,
      targetDepthMeters: 0.12,
      alignFootprint: true,
    ),
    'exhaust': const MeshProfile(
      iconName: 'exhaust',
      assetPath: '$hvacDir/extract_fan_grille.glb',
      heightMeters: 0.32,
      role: MeshSimRole.emitter,
      airflowSolid: 0,
      lightTransmit: 0.12,
      wallCut: WallCutKind.niche,
      wallCutPadMeters: 0.012,
      clearWidthMeters: 0.45,
      clearHeightMeters: 0.32,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.45,
      targetDepthMeters: 0.12,
      alignFootprint: true,
    ),
    'door': const MeshProfile(
      iconName: 'door',
      // doorway.glb is the leaf/frame; doorwayOpen / wallDoorway are full wall slabs.
      assetPath: '$kenneyDir/doorway.glb',
      heightMeters: 1.92,
      role: MeshSimRole.opening,
      lightTransmit: 0.95,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      wallCutPadMeters: 0.01,
      clearWidthMeters: 0.9,
      clearHeightMeters: 1.92,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.9,
      targetDepthMeters: 0.14,
      alignFootprint: true,
    ),
    'window': const MeshProfile(
      iconName: 'window',
      assetPath: '$kenneyDir/wallWindow.glb',
      heightMeters: 1.1,
      role: MeshSimRole.glass,
      lightTransmit: 0.82,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      wallCutPadMeters: 0.01,
      // ~1 grid cell — wider clearWidth made every Orbit window a flat slab.
      clearWidthMeters: 0.7,
      clearHeightMeters: 1.1,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.7,
      targetDepthMeters: 0.14,
      // Without this, E/W walls leave Kenney's long-Z axis pointing into the room.
      alignFootprint: true,
    ),
    'smartBlinds': const MeshProfile(
      iconName: 'smartBlinds',
      assetPath: '$kenneyDir/wallWindowSlide.glb',
      heightMeters: 1.1,
      role: MeshSimRole.glass,
      lightTransmit: 0.35,
      airflowSolid: 0,
      wallCut: WallCutKind.through,
      wallCutPadMeters: 0.01,
      clearWidthMeters: 0.7,
      clearHeightMeters: 1.1,
      fitMode: MeshFitMode.wallOpening,
      targetWidthMeters: 0.7,
      targetDepthMeters: 0.14,
      alignFootprint: true,
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
          fitMode: MeshFitMode.uniform,
        );
  }

  static MeshProfile profileForItem(FurnitureItem item) =>
      profileFor(item.iconName);

  static String? assetForIcon(String iconName) => profileFor(iconName).assetPath;

  static double defaultHeightMeters(String iconName) =>
      profileFor(iconName).heightMeters;

  /// Snap metres → grid cells (0.05 resolution) for Orbit / Rig footprints.
  static double cellsFromMeters(double meters) {
    final raw = meters / RoomScale.cellMeters;
    return (raw * 20).round() / 20.0;
  }

  /// Default Orbit footprint (cells) for an icon — metre targets when set.
  static ({double width, double depth}) orbitFootprint(
    String iconName, {
    double fallbackWidth = 1,
    double fallbackDepth = 1,
  }) {
    final p = profileFor(iconName);
    return (
      width: p.footprintWidthCells ?? fallbackWidth,
      depth: p.footprintDepthCells ?? fallbackDepth,
    );
  }

  /// All catalog keys (for audits / tests).
  static Iterable<String> get catalogKeys => _profiles.keys;

  /// Base URL for textures / GLBs inside the Model WebView.
  /// Android stages assets to a real temp folder so `../gltf/` XHR works.
  static String get sceneAssetBase => '../gltf/';

  static String? sceneUrlForIcon(String iconName) {
    final asset = assetForIcon(iconName);
    if (asset == null) return null;
    final rel = asset.replaceFirst('assets/gltf/', '');
    return '$sceneAssetBase$rel';
  }
}
