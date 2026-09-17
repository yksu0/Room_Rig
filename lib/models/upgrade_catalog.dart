// Demo upgrade shop — prices are ballpark retail placeholders; boosts are
// authored score tags (not measured CFD / lux / ergonomics lab points).
import 'rig_catalog.dart';

class UpgradeSpec {
  final String name;
  final String iconName;
  final String furnitureId;
  final String type;
  final String desc;
  final double airflowBoost;
  final double lightingBoost;
  final double ergonomicsBoost;
  /// Ballpark USD list-price placeholder for demos (not live retail).
  final double price;

  const UpgradeSpec({
    required this.name,
    required this.iconName,
    required this.furnitureId,
    required this.type,
    required this.desc,
    required this.airflowBoost,
    required this.lightingBoost,
    required this.ergonomicsBoost,
    required this.price,
  });

  Map<String, dynamic> toMutableMap() => {
        'name': name,
        'iconName': iconName,
        'furnitureId': furnitureId,
        'type': type,
        'desc': desc,
        'airflowBoost': airflowBoost,
        'lightingBoost': lightingBoost,
        'ergonomicsBoost': ergonomicsBoost,
        'price': price,
        'added': false,
      };
}

/// Shared Hub badge strings (keep UI + QA tests in sync).
class HubScoreLabels {
  static const roughEst = 'ROUGH EST.';
  static const benchOk = 'BENCH OK';
  static const roughSubtitle = 'Run Bench to lock scores after layout changes.';
  static const honestyNote =
      'ROUGH EST. = impact estimate until Bench Apply; BENCH OK = last Apply locked sim scores.';
}

class UpgradeCatalog {
  UpgradeCatalog._();

  static const honestyNote =
      'Prices are demo ballparks; boost tags are authored placeholders — not measured performance.';

  /// Impact on furniture when Place'd: boost / [boostToImpactDivisor].
  static const boostToImpactDivisor = 20.0;

  static const List<UpgradeSpec> specs = [
    UpgradeSpec(
      name: 'Air Circulator Fan',
      iconName: 'fan',
      furnitureId: 'upg_fan',
      type: 'airflow',
      desc: 'Places a stand fan on your Rig — oscillates into open floor',
      airflowBoost: 14,
      lightingBoost: 0,
      ergonomicsBoost: 0,
      price: 69,
    ),
    UpgradeSpec(
      name: 'Smart Air Purifier',
      iconName: 'purifier',
      furnitureId: 'upg_purifier',
      type: 'airflow',
      desc: 'Adds a floor purifier that also stirs room air',
      airflowBoost: 10,
      lightingBoost: 0,
      ergonomicsBoost: 4,
      price: 199,
    ),
    UpgradeSpec(
      name: 'Smart Light Bar',
      iconName: 'lightBar',
      furnitureId: 'upg_light_bar',
      type: 'lighting',
      desc: 'Bias light near the desk for task illumination',
      airflowBoost: 0,
      lightingBoost: 16,
      ergonomicsBoost: 5,
      price: 89,
    ),
    UpgradeSpec(
      name: 'Diffused Floor Lamp',
      iconName: 'floorLamp',
      furnitureId: 'upg_floor_lamp',
      type: 'lighting',
      desc: 'Soft ambient lamp on the Rig floor plan',
      airflowBoost: 0,
      lightingBoost: 11,
      ergonomicsBoost: 2,
      price: 75,
    ),
    UpgradeSpec(
      name: 'Monitor Arm',
      iconName: 'monitorArm',
      furnitureId: 'upg_monitor_arm',
      type: 'ergonomics',
      desc: 'Monitor arm at the desk — frees surface, better eye line',
      airflowBoost: 4,
      lightingBoost: 0,
      ergonomicsBoost: 18,
      price: 119,
    ),
    UpgradeSpec(
      name: 'Cable Tray',
      iconName: 'cableTray',
      furnitureId: 'upg_cable_tray',
      type: 'ergonomics',
      desc: 'Under-desk tray that clears walk/air paths',
      airflowBoost: 6,
      lightingBoost: 0,
      ergonomicsBoost: 9,
      price: 35,
    ),
    UpgradeSpec(
      name: 'Anti-Fatigue Mat',
      iconName: 'mat',
      furnitureId: 'upg_mat',
      type: 'ergonomics',
      desc: 'Standing mat at the work zone',
      airflowBoost: 0,
      lightingBoost: 0,
      ergonomicsBoost: 14,
      price: 45,
    ),
    UpgradeSpec(
      name: 'Smart Blinds',
      iconName: 'smartBlinds',
      furnitureId: 'upg_blinds',
      type: 'lighting',
      desc: 'Blinds on the window wall to cut glare',
      airflowBoost: 2,
      lightingBoost: 13,
      ergonomicsBoost: 0,
      price: 229,
    ),
  ];

  static List<Map<String, dynamic>> mutableShop() =>
      specs.map((s) => s.toMutableMap()).toList();

  static double impactFromBoost(double boost) => boost / boostToImpactDivisor;

  /// Catalog SKUs that upgrades place — used by coverage tests.
  static Set<String> get furnitureIds =>
      specs.map((s) => s.furnitureId).toSet();

  static bool isKnownFurnitureId(String id) =>
      furnitureIds.contains(id) || RigCatalog.items.any((e) => e.baseId == id);
}
