// Maps Rig furniture icon names → Kenney CC0 GLB assets (self-contained materials).
// Source: Kenney Furniture Kit (CC0) via kenney_assets-classified mirror.
// Room shell textures: Poly Haven wood_floor / plastered_wall (CC0).

class GltfCatalog {
  GltfCatalog._();

  static const kenneyDir = 'assets/gltf/kenney';

  /// Flutter asset path for a furniture [iconName], or null for procedural placeholder.
  static String? assetForIcon(String iconName) {
    switch (iconName) {
      case 'desk':
        return '$kenneyDir/desk.glb';
      case 'chair':
        return '$kenneyDir/chairDesk.glb';
      case 'bed':
        return '$kenneyDir/bedDouble.glb';
      case 'sofa':
        return '$kenneyDir/loungeSofa.glb';
      case 'shelf':
      case 'bookshelf':
        return '$kenneyDir/bookcaseOpen.glb';
      case 'wardrobe':
        return '$kenneyDir/cabinetBedDrawer.glb';
      case 'lamp':
        return '$kenneyDir/lampRoundTable.glb';
      case 'floorLamp':
        return '$kenneyDir/lampSquareFloor.glb';
      case 'plant':
        return '$kenneyDir/pottedPlant.glb';
      case 'monitor':
        return '$kenneyDir/computerScreen.glb';
      case 'tv':
        return '$kenneyDir/televisionModern.glb';
      case 'pc':
        return '$kenneyDir/speaker.glb'; // closest small tower-like prop
      case 'fan':
        return '$kenneyDir/ceilingFan.glb';
      case 'door':
        return '$kenneyDir/doorway.glb';
      case 'window':
        return '$kenneyDir/wallWindow.glb';
      case 'table':
        return '$kenneyDir/tableCoffee.glb';
      default:
        return null;
    }
  }

  /// Approximate mesh height in meters for fitting (Kenney units are ~meters).
  static double defaultHeightMeters(String iconName) {
    switch (iconName) {
      case 'bed':
        return 0.55;
      case 'sofa':
        return 0.85;
      case 'desk':
      case 'table':
        return 0.75;
      case 'chair':
        return 1.05;
      case 'wardrobe':
      case 'shelf':
      case 'bookshelf':
        return 1.8;
      case 'floorLamp':
        return 1.55;
      case 'lamp':
        return 0.45;
      case 'plant':
        return 0.7;
      case 'monitor':
      case 'tv':
        return 0.5;
      case 'pc':
        return 0.45;
      case 'fan':
        return 0.35;
      case 'door':
        return 2.1;
      case 'window':
        return 1.2;
      default:
        return 0.9;
    }
  }
}
