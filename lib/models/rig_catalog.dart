// lib/models/rig_catalog.dart
// v1 set — a few of each filter, enough for a bedroom or desk room.
// Footprints come from GltfCatalog metre targets so Orbit matches Model.
import '../services/gltf_catalog.dart';
import 'room_model.dart';

class RigCatalogEntry {
  /// Base id; a suffix is appended when the room already holds one.
  final String baseId;
  final String name;
  final String iconName;

  /// 'airflow' | 'lighting' | 'ergonomics' | 'neutral'
  final String category;
  final double width;
  final double height;
  final double airflowImpact;
  final double lightingImpact;
  final double ergonomicsImpact;
  final double cost;
  final String description;

  RigCatalogEntry({
    required this.baseId,
    required this.name,
    required this.iconName,
    required this.category,
    this.width = 1,
    this.height = 1,
    this.airflowImpact = 0,
    this.lightingImpact = 0,
    this.ergonomicsImpact = 0,
    this.cost = 0,
    this.description = '',
  });

  /// Footprint from MeshProfile metre targets when available.
  factory RigCatalogEntry.fromCatalog({
    required String baseId,
    required String name,
    required String iconName,
    required String category,
    double fallbackWidth = 1,
    double fallbackDepth = 1,
    double airflowImpact = 0,
    double lightingImpact = 0,
    double ergonomicsImpact = 0,
    double cost = 0,
    String description = '',
  }) {
    final fp = GltfCatalog.orbitFootprint(
      iconName,
      fallbackWidth: fallbackWidth,
      fallbackDepth: fallbackDepth,
    );
    return RigCatalogEntry(
      baseId: baseId,
      name: name,
      iconName: iconName,
      category: category,
      width: fp.width,
      height: fp.depth,
      airflowImpact: airflowImpact,
      lightingImpact: lightingImpact,
      ergonomicsImpact: ergonomicsImpact,
      cost: cost,
      description: description,
    );
  }

  FurnitureItem toFurniture({
    required String id,
    required double gridX,
    required double gridY,
  }) {
    return FurnitureItem(
      id: id,
      name: name,
      iconName: iconName,
      category: category,
      gridX: gridX,
      gridY: gridY,
      width: width,
      height: height,
      airflowImpact: airflowImpact,
      lightingImpact: lightingImpact,
      ergonomicsImpact: ergonomicsImpact,
      cost: cost,
      description: description.isEmpty ? name : description,
    );
  }
}

class RigCatalog {
  RigCatalog._();

  static final items = <RigCatalogEntry>[
    RigCatalogEntry.fromCatalog(
      baseId: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'ergonomics',
      fallbackWidth: 2,
      fallbackDepth: 1,
      ergonomicsImpact: 0.6,
      cost: 220,
      description: 'Work surface — drop a monitor, PC or lamp on it',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'chair',
      name: 'Chair',
      iconName: 'chair',
      category: 'ergonomics',
      ergonomicsImpact: 0.7,
      cost: 180,
      description: 'Seat at the desk — leave pull-back room',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'monitor',
      name: 'Monitor',
      iconName: 'monitor',
      category: 'ergonomics',
      fallbackWidth: 1.25,
      fallbackDepth: 0.35,
      ergonomicsImpact: 0.4,
      lightingImpact: -0.1,
      cost: 260,
      description: 'Sits on a desk — thin screen, not a floor block',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'pc',
      name: 'PC Tower',
      iconName: 'pc',
      category: 'airflow',
      fallbackWidth: 0.35,
      fallbackDepth: 0.75,
      airflowImpact: -0.5,
      cost: 900,
      description: 'Heat source — Auto-Rig parks it on the desk when one is present',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'bed',
      name: 'Bed',
      iconName: 'bed',
      category: 'neutral',
      fallbackWidth: 2,
      fallbackDepth: 2,
      airflowImpact: -0.3,
      cost: 400,
      description: 'Low wide footprint — keep walk paths around it',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'sofa',
      name: 'Sofa',
      iconName: 'sofa',
      category: 'neutral',
      fallbackWidth: 2,
      fallbackDepth: 1,
      airflowImpact: -0.2,
      cost: 520,
      description: 'Low seat along a wall',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'table',
      name: 'Table',
      iconName: 'table',
      category: 'neutral',
      fallbackWidth: 2,
      fallbackDepth: 1,
      cost: 180,
      description: 'Lounge table — holds TV, plant, or a small lamp',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'wardrobe',
      name: 'Wardrobe',
      iconName: 'wardrobe',
      category: 'neutral',
      fallbackWidth: 1.5,
      fallbackDepth: 0.9,
      airflowImpact: -0.5,
      lightingImpact: -0.4,
      cost: 480,
      description: 'Full-height storage',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'shelf',
      name: 'Shelf',
      iconName: 'shelf',
      category: 'neutral',
      fallbackWidth: 1.4,
      fallbackDepth: 0.65,
      airflowImpact: -0.4,
      lightingImpact: -0.3,
      cost: 150,
      description: 'Tall open storage',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'plant',
      name: 'Plant',
      iconName: 'plant',
      category: 'neutral',
      cost: 35,
      description: 'Small pot — stacks on the lounge table',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'tv',
      name: 'TV',
      iconName: 'tv',
      category: 'lighting',
      fallbackWidth: 1.85,
      fallbackDepth: 0.45,
      lightingImpact: 0.15,
      cost: 400,
      description: 'Wide thin screen — sits on the lounge table',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'door',
      name: 'Door',
      iconName: 'door',
      category: 'neutral',
      fallbackWidth: 1.5,
      fallbackDepth: 1,
      airflowImpact: 0.3,
      ergonomicsImpact: 0.2,
      cost: 180,
      description: 'Entry opening — Invasive mode to move',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'window',
      name: 'Window',
      iconName: 'window',
      category: 'lighting',
      fallbackWidth: 1.9,
      fallbackDepth: 1,
      lightingImpact: 0.85,
      airflowImpact: 0.5,
      cost: 280,
      description: 'Daylight opening — seeps a little if the room is over- or under-pressured',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'ac',
      name: 'Wall AC',
      iconName: 'ac',
      category: 'airflow',
      fallbackWidth: 1.5,
      fallbackDepth: 1,
      airflowImpact: 0.9,
      cost: 700,
      description: 'Wall cold supply — Invasive mode to move',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'intake',
      name: 'Intake Vent',
      iconName: 'intake',
      category: 'airflow',
      fallbackWidth: 0.75,
      fallbackDepth: 1,
      airflowImpact: 0.7,
      cost: 90,
      description: 'Wall supply — outdoor air in. Pressurizes the room so windows leak out',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'exhaust',
      name: 'Exhaust Fan',
      iconName: 'exhaust',
      category: 'airflow',
      fallbackWidth: 0.75,
      fallbackDepth: 1,
      airflowImpact: 0.65,
      cost: 85,
      description: 'Wall extract — room air out. Windows then leak in to replace it',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'portable_ac',
      name: 'Portable AC',
      iconName: 'ac',
      category: 'airflow',
      airflowImpact: 0.75,
      cost: 380,
      description: 'Floor cold jet — aim with yaw',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'fan',
      name: 'Stand Fan',
      iconName: 'fan',
      category: 'airflow',
      airflowImpact: 0.6,
      cost: 70,
      description: 'Pole + disc — aim with yaw',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'space_heater',
      name: 'Space Heater',
      iconName: 'heater',
      category: 'airflow',
      airflowImpact: -0.7,
      cost: 80,
      description: 'Short floor heater — aim with yaw',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'lamp',
      name: 'Task Lamp',
      iconName: 'lamp',
      category: 'lighting',
      lightingImpact: 0.7,
      cost: 60,
      description: 'Desk lamp — snaps onto a desk',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'floor_lamp',
      name: 'Floor Lamp',
      iconName: 'floorLamp',
      category: 'lighting',
      lightingImpact: 0.55,
      cost: 80,
      description: 'Tall pole lamp on the floor',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'ceiling_light',
      name: 'Ceiling Light',
      iconName: 'ceilingLight',
      category: 'lighting',
      lightingImpact: 0.8,
      cost: 90,
      description: 'Disc on the ceiling — Invasive mode to move',
    ),
    RigCatalogEntry.fromCatalog(
      baseId: 'purifier',
      name: 'Air Purifier',
      iconName: 'purifier',
      category: 'airflow',
      airflowImpact: 0.4,
      cost: 220,
      description: 'Floor scrubber — keep clear of walls',
    ),
  ];

  static bool isV1Item(FurnitureItem f) {
    final id = f.id.toLowerCase();
    if (id.startsWith('custom')) return true;
    if (id.startsWith('scan')) return true;
    // Placed upgrades must survive Apply / room load / persist.
    if (id.startsWith('upg_')) return true;
    final hay = '$id ${f.name} ${f.iconName}'.toLowerCase();
    // Detector-native classes (Room Rig YOLO) must survive Scan → Rig commit.
    // Do not reject purifier / smartBlinds — they are first-class Scan labels.
    if (f.iconName == 'kitchen' ||
        hay.contains('kitchen') ||
        hay.contains('evaporative') ||
        hay.contains('mini fridge') ||
        hay.contains('mini_fridge') ||
        RegExp(r'\b(nas|console)\b').hasMatch(hay)) {
      return false;
    }
    // Radiator without vent/intake context was demo junk; keep explicit heater SKUs.
    if (hay.contains('radiator') &&
        f.iconName != 'heater' &&
        !hay.contains('heater') &&
        !hay.contains('vent') &&
        !hay.contains('intake')) {
      return false;
    }
    const keep = [
      'desk',
      'chair',
      'monitor',
      'pc',
      'bed',
      'sofa',
      'table',
      'wardrobe',
      'shelf',
      'bookshelf',
      'plant',
      'tv',
      'door',
      'window',
      'ac',
      'intake',
      'exhaust',
      'fan',
      'heater',
      'vent',
      'purifier',
      'blinds',
      'smartblinds',
      'lamp',
      'light',
    ];
    return keep.any(hay.contains);
  }

  static List<FurnitureItem> retainV1(List<FurnitureItem> items) =>
      [for (final f in items) if (isV1Item(f)) f];
}
