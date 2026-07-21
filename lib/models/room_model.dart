// lib/models/room_model.dart

enum RoomPreset {
  gamingSetup,
  homeOffice,
  studioApartment,
  minimalistBedroom,
}

class FurnitureItem {
  final String id;
  final String name;
  final String iconName; // used by furnitureSvgFor()
  final String category; // 'airflow' | 'lighting' | 'ergonomics' | 'neutral'
  double gridX;
  double gridY;
  final double width;
  final double height;
  final double airflowImpact;
  final double lightingImpact;
  final double ergonomicsImpact;
  final String description;
  final double cost;

  FurnitureItem({
    required this.id,
    required this.name,
    required this.iconName,
    required this.category,
    required this.gridX,
    required this.gridY,
    this.width = 1.0,
    this.height = 1.0,
    this.airflowImpact = 0.0,
    this.lightingImpact = 0.0,
    this.ergonomicsImpact = 0.0,
    this.description = 'Active Room Component',
    this.cost = 100.0,
  });

  FurnitureItem copyWith({double? gridX, double? gridY}) {
    return FurnitureItem(
      id: id,
      name: name,
      iconName: iconName,
      category: category,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      width: width,
      height: height,
      airflowImpact: airflowImpact,
      lightingImpact: lightingImpact,
      ergonomicsImpact: ergonomicsImpact,
      description: description,
      cost: cost,
    );
  }
}

class RoomData {
  final String name;
  final String subtitle;
  final String iconName; // used by presetSvgFor()
  final int gridCols;
  final int gridRows;
  final List<FurnitureItem> furniture;

  const RoomData({
    required this.name,
    required this.subtitle,
    required this.iconName,
    required this.gridCols,
    required this.gridRows,
    required this.furniture,
  });
}

class RoomPresets {
  static RoomData getPreset(RoomPreset preset) {
    switch (preset) {
      case RoomPreset.gamingSetup:
        return RoomData(
          name: 'Gaming Setup',
          subtitle: 'High-performance gaming room with RGB everything',
          iconName: 'gaming setup',
          gridCols: 6,
          gridRows: 8,
          furniture: [
            FurnitureItem(id: 'desk', name: 'Gaming Desk', iconName: 'desk', category: 'ergonomics', gridX: 1, gridY: 1, width: 2, height: 1, ergonomicsImpact: 0.6, lightingImpact: -0.1, cost: 299, description: 'Spacious desk designed for multi-monitor setups.'),
            FurnitureItem(id: 'chair', name: 'Gaming Chair', iconName: 'chair', category: 'ergonomics', gridX: 1, gridY: 2, ergonomicsImpact: 0.8, airflowImpact: -0.2, cost: 349, description: 'Ergonomic bucket-seat design with lumbar support.'),
            FurnitureItem(id: 'bed', name: 'Bed', iconName: 'bed', category: 'neutral', gridX: 3, gridY: 4, width: 2, height: 2, airflowImpact: -0.3, ergonomicsImpact: -0.2, cost: 599, description: 'Essential sleeping comfort zone; obstructs some airflow.'),
            FurnitureItem(id: 'pc', name: 'PC Tower', iconName: 'pc', category: 'airflow', gridX: 0, gridY: 1, airflowImpact: -0.4, lightingImpact: 0.1, cost: 1500, description: 'Main processing powerhouse; generates exhaust heat.'),
            FurnitureItem(id: 'ac', name: 'AC Unit', iconName: 'ac', category: 'airflow', gridX: 5, gridY: 0, airflowImpact: 0.9, cost: 450, description: 'Generates cold air streams to cool down the room rig.'),
            FurnitureItem(id: 'window', name: 'Window', iconName: 'window', category: 'lighting', gridX: 2, gridY: 0, lightingImpact: 0.8, airflowImpact: 0.5, cost: 300, description: 'Provides natural light and ambient ventilation.'),
            FurnitureItem(id: 'lamp', name: 'LED Strip', iconName: 'lamp', category: 'lighting', gridX: 3, gridY: 1, lightingImpact: 0.5, cost: 49, description: 'RGB ambient lighting to customize workspace mood.'),
            FurnitureItem(id: 'shelf', name: 'Shelf', iconName: 'shelf', category: 'neutral', gridX: 5, gridY: 3, airflowImpact: -0.2, cost: 119, description: 'Storage unit; blockages can redirect airflow path.'),
            FurnitureItem(id: 'fan', name: 'Stand Fan', iconName: 'fan', category: 'airflow', gridX: 4, gridY: 5, airflowImpact: 0.55, cost: 45, description: 'Oscillating pedestal fan; sweeps ~45° to push air around the room.'),
          ],
        );
      case RoomPreset.homeOffice:
        return RoomData(
          name: 'Home Office',
          subtitle: 'Productive workspace optimized for deep work',
          iconName: 'home office',
          gridCols: 6,
          gridRows: 8,
          furniture: [
            FurnitureItem(id: 'desk', name: 'Standing Desk', iconName: 'desk', category: 'ergonomics', gridX: 0, gridY: 1, width: 2, height: 1, ergonomicsImpact: 0.9, lightingImpact: 0.1, cost: 499, description: 'Dual-motor standing desk for healthy posture transitions.'),
            FurnitureItem(id: 'chair', name: 'Ergonomic Chair', iconName: 'chair', category: 'ergonomics', gridX: 0, gridY: 2, ergonomicsImpact: 0.9, cost: 699, description: 'High-back mesh design, optimal comfort and posture alignment.'),
            FurnitureItem(id: 'monitor', name: 'Monitor Arm', iconName: 'monitor', category: 'ergonomics', gridX: 1, gridY: 1, ergonomicsImpact: 0.7, cost: 129, description: 'Frees up desk real estate and positions screen at eye level.'),
            FurnitureItem(id: 'window', name: 'Large Window', iconName: 'window', category: 'lighting', gridX: 3, gridY: 0, width: 2, lightingImpact: 0.9, airflowImpact: 0.7, cost: 400, description: 'Wide exterior window for maximum natural light spread.'),
            FurnitureItem(id: 'plant', name: 'Plant', iconName: 'plant', category: 'airflow', gridX: 5, gridY: 2, airflowImpact: 0.3, ergonomicsImpact: 0.2, cost: 39, description: 'Breathes life into the office and purifies ambient air.'),
            FurnitureItem(id: 'bookshelf', name: 'Bookshelf', iconName: 'bookshelf', category: 'neutral', gridX: 4, gridY: 3, width: 2, airflowImpact: -0.3, cost: 179, description: 'Heavy storage shelving; obstructs direct ventilation lines.'),
            FurnitureItem(id: 'lamp', name: 'Desk Lamp', iconName: 'lamp', category: 'lighting', gridX: 2, gridY: 1, lightingImpact: 0.6, cost: 59, description: 'Focused task lighting to avoid screen glare.'),
            FurnitureItem(id: 'sofa', name: 'Sofa', iconName: 'sofa', category: 'neutral', gridX: 1, gridY: 5, width: 2, airflowImpact: -0.3, ergonomicsImpact: 0.2, cost: 499, description: 'Secondary comfortable seating area for relaxation breaks.'),
          ],
        );
      case RoomPreset.studioApartment:
        return RoomData(
          name: 'Studio Apartment',
          subtitle: 'Compact living space with multi-functional zones',
          iconName: 'studio apartment',
          gridCols: 6,
          gridRows: 8,
          furniture: [
            FurnitureItem(id: 'bed', name: 'Murphy Bed', iconName: 'bed', category: 'neutral', gridX: 4, gridY: 0, width: 2, height: 2, airflowImpact: -0.2, ergonomicsImpact: 0.3, cost: 999, description: 'Foldable wall bed; optimizes space efficiency.'),
            FurnitureItem(id: 'sofa', name: 'Compact Sofa', iconName: 'sofa', category: 'neutral', gridX: 1, gridY: 3, width: 2, ergonomicsImpact: 0.4, cost: 349, description: 'Space-saving sofa, provides essential lounging comfort.'),
            FurnitureItem(id: 'kitchen', name: 'Kitchen Counter', iconName: 'kitchen', category: 'neutral', gridX: 0, gridY: 0, width: 1, height: 3, airflowImpact: -0.1, cost: 1200, description: 'Essential cooking workspace; static layout component.'),
            FurnitureItem(id: 'desk', name: 'Fold Desk', iconName: 'desk', category: 'ergonomics', gridX: 3, gridY: 4, ergonomicsImpact: 0.5, cost: 149, description: 'Collapsible wall-mount desk to maximize walking path clearance.'),
            FurnitureItem(id: 'window', name: 'Window', iconName: 'window', category: 'lighting', gridX: 2, gridY: 0, width: 2, lightingImpact: 0.9, airflowImpact: 0.8, cost: 300, description: 'Provides natural light and ambient ventilation.'),
            FurnitureItem(id: 'plant', name: 'Plant', iconName: 'plant', category: 'airflow', gridX: 5, gridY: 5, airflowImpact: 0.3, cost: 29, description: 'Aesthetic touch that improves airflow freshness.'),
            FurnitureItem(id: 'lamp', name: 'Floor Lamp', iconName: 'lamp', category: 'lighting', gridX: 0, gridY: 4, lightingImpact: 0.5, cost: 89, description: 'Diffused corner illumination to visually widen the space.'),
          ],
        );
      case RoomPreset.minimalistBedroom:
        return RoomData(
          name: 'Minimalist Bedroom',
          subtitle: 'Clean, calm sleeping environment with zen vibes',
          iconName: 'minimalist bedroom',
          gridCols: 6,
          gridRows: 8,
          furniture: [
            FurnitureItem(id: 'bed', name: 'Low Bed Frame', iconName: 'bed', category: 'neutral', gridX: 1, gridY: 2, width: 3, height: 2, ergonomicsImpact: 0.6, airflowImpact: 0.1, cost: 650, description: 'Low-profile frame to keep vertical space open and calm.'),
            FurnitureItem(id: 'window', name: 'Wide Window', iconName: 'window', category: 'lighting', gridX: 2, gridY: 0, width: 2, lightingImpact: 1.0, airflowImpact: 0.7, cost: 450, description: 'Large architectural window providing maximum light exposure.'),
            FurnitureItem(id: 'plant', name: 'Peace Lily', iconName: 'plant', category: 'airflow', gridX: 5, gridY: 2, airflowImpact: 0.4, ergonomicsImpact: 0.3, cost: 35, description: 'Improves oxygen circulation in the sleeping zone.'),
            FurnitureItem(id: 'lamp', name: 'Ambient Lamp', iconName: 'lamp', category: 'lighting', gridX: 0, gridY: 2, lightingImpact: 0.4, cost: 69, description: 'Warm-spectrum lighting helper to optimize circadian rhythm.'),
            FurnitureItem(id: 'wardrobe', name: 'Wardrobe', iconName: 'wardrobe', category: 'neutral', gridX: 0, gridY: 4, height: 2, airflowImpact: -0.2, cost: 390, description: 'Sleek storage cabinet; blocks direct draft paths.'),
          ],
        );
    }
  }

  static List<RoomData> get all => [
    getPreset(RoomPreset.gamingSetup),
    getPreset(RoomPreset.homeOffice),
    getPreset(RoomPreset.studioApartment),
    getPreset(RoomPreset.minimalistBedroom),
  ];
}
