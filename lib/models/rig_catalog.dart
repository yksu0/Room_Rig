// lib/models/rig_catalog.dart
// v1 set — a few of each filter, enough for a bedroom or desk room.
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

  const RigCatalogEntry({
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

  static const items = <RigCatalogEntry>[
    RigCatalogEntry(
      baseId: 'desk',
      name: 'Desk',
      iconName: 'desk',
      category: 'ergonomics',
      width: 2,
      ergonomicsImpact: 0.6,
      cost: 220,
      description: 'Work surface — drop a monitor, PC or lamp on it',
    ),
    RigCatalogEntry(
      baseId: 'chair',
      name: 'Chair',
      iconName: 'chair',
      category: 'ergonomics',
      ergonomicsImpact: 0.7,
      cost: 180,
      description: 'Seat at the desk — leave pull-back room',
    ),
    RigCatalogEntry(
      baseId: 'monitor',
      name: 'Monitor',
      iconName: 'monitor',
      category: 'ergonomics',
      ergonomicsImpact: 0.4,
      lightingImpact: -0.1,
      cost: 260,
      description: 'Sits on a desk — thin screen, not a floor block',
    ),
    RigCatalogEntry(
      baseId: 'pc',
      name: 'PC Tower',
      iconName: 'pc',
      category: 'airflow',
      airflowImpact: -0.5,
      cost: 900,
      description: 'Heat source — on the desk or on the floor beside it',
    ),
    RigCatalogEntry(
      baseId: 'bed',
      name: 'Bed',
      iconName: 'bed',
      category: 'neutral',
      width: 2,
      height: 2,
      airflowImpact: -0.3,
      cost: 400,
      description: 'Low wide footprint — keep walk paths around it',
    ),
    RigCatalogEntry(
      baseId: 'sofa',
      name: 'Sofa',
      iconName: 'sofa',
      category: 'neutral',
      width: 2,
      airflowImpact: -0.2,
      cost: 520,
      description: 'Low seat along a wall',
    ),
    RigCatalogEntry(
      baseId: 'table',
      name: 'Table',
      iconName: 'desk',
      category: 'neutral',
      width: 2,
      height: 1,
      cost: 180,
      description: 'Dining or coffee table — also holds a lamp',
    ),
    RigCatalogEntry(
      baseId: 'wardrobe',
      name: 'Wardrobe',
      iconName: 'wardrobe',
      category: 'neutral',
      width: 2,
      airflowImpact: -0.5,
      lightingImpact: -0.4,
      cost: 480,
      description: 'Full-height storage',
    ),
    RigCatalogEntry(
      baseId: 'shelf',
      name: 'Shelf',
      iconName: 'shelf',
      category: 'neutral',
      airflowImpact: -0.4,
      lightingImpact: -0.3,
      cost: 150,
      description: 'Tall open storage',
    ),
    RigCatalogEntry(
      baseId: 'plant',
      name: 'Plant',
      iconName: 'plant',
      category: 'neutral',
      cost: 35,
      description: 'Small pot',
    ),
    RigCatalogEntry(
      baseId: 'tv',
      name: 'TV',
      iconName: 'tv',
      category: 'lighting',
      width: 2,
      lightingImpact: 0.15,
      cost: 400,
      description: 'Wide thin screen on a stand',
    ),
    RigCatalogEntry(
      baseId: 'door',
      name: 'Door',
      iconName: 'door',
      category: 'neutral',
      height: 1,
      airflowImpact: 0.3,
      ergonomicsImpact: 0.2,
      cost: 180,
      description: 'Entry opening — Invasive mode to move',
    ),
    RigCatalogEntry(
      baseId: 'window',
      name: 'Window',
      iconName: 'window',
      category: 'lighting',
      width: 2,
      lightingImpact: 0.85,
      airflowImpact: 0.5,
      cost: 280,
      description: 'Daylight opening — seeps a little if the room is over- or under-pressured',
    ),
    RigCatalogEntry(
      baseId: 'ac',
      name: 'Wall AC',
      iconName: 'ac',
      category: 'airflow',
      airflowImpact: 0.9,
      cost: 700,
      description: 'Wall cold supply — Invasive mode to move',
    ),
    RigCatalogEntry(
      baseId: 'intake',
      name: 'Intake Vent',
      iconName: 'intake',
      category: 'airflow',
      airflowImpact: 0.7,
      cost: 90,
      description: 'Wall supply — outdoor air in. Pressurizes the room so windows leak out',
    ),
    RigCatalogEntry(
      baseId: 'exhaust',
      name: 'Exhaust Fan',
      iconName: 'exhaust',
      category: 'airflow',
      airflowImpact: 0.65,
      cost: 85,
      description: 'Wall extract — room air out. Windows then leak in to replace it',
    ),
    RigCatalogEntry(
      baseId: 'portable_ac',
      name: 'Portable AC',
      iconName: 'ac',
      category: 'airflow',
      airflowImpact: 0.75,
      cost: 380,
      description: 'Floor cold jet — aim with yaw',
    ),
    RigCatalogEntry(
      baseId: 'fan',
      name: 'Stand Fan',
      iconName: 'fan',
      category: 'airflow',
      airflowImpact: 0.6,
      cost: 70,
      description: 'Pole + disc — aim with yaw',
    ),
    RigCatalogEntry(
      baseId: 'space_heater',
      name: 'Space Heater',
      iconName: 'floorLamp',
      category: 'airflow',
      airflowImpact: -0.7,
      cost: 80,
      description: 'Short floor heater — aim with yaw',
    ),
    RigCatalogEntry(
      baseId: 'lamp',
      name: 'Task Lamp',
      iconName: 'lamp',
      category: 'lighting',
      lightingImpact: 0.7,
      cost: 60,
      description: 'Desk lamp — snaps onto a desk',
    ),
    RigCatalogEntry(
      baseId: 'floor_lamp',
      name: 'Floor Lamp',
      iconName: 'floorLamp',
      category: 'lighting',
      lightingImpact: 0.55,
      cost: 80,
      description: 'Tall pole lamp on the floor',
    ),
    RigCatalogEntry(
      baseId: 'ceiling_light',
      name: 'Ceiling Light',
      iconName: 'ceilingLight',
      category: 'lighting',
      lightingImpact: 0.8,
      cost: 90,
      description: 'Disc on the ceiling — Invasive mode to move',
    ),
  ];

  static bool isV1Item(FurnitureItem f) {
    final id = f.id.toLowerCase();
    if (id.startsWith('custom')) return true;
    if (id.startsWith('scan')) return true;
    if (id.startsWith('upg_')) return false;
    final hay = '$id ${f.name} ${f.iconName}'.toLowerCase();
    if (f.iconName == 'kitchen' ||
        f.iconName == 'purifier' ||
        f.iconName == 'mat' ||
        f.iconName == 'smartBlinds' ||
        f.iconName == 'cableTray' ||
        hay.contains('kitchen') ||
        hay.contains('purifier') ||
        hay.contains('evaporative') ||
        hay.contains('radiator') ||
        hay.contains('mini fridge') ||
        hay.contains('mini_fridge') ||
        RegExp(r'\b(nas|console)\b').hasMatch(hay)) {
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
      'lamp',
      'light',
    ];
    return keep.any(hay.contains);
  }

  static List<FurnitureItem> retainV1(List<FurnitureItem> items) =>
      [for (final f in items) if (isV1Item(f)) f];
}
