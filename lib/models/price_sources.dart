// lib/models/price_sources.dart
// Short, in-app hints for where each peso estimate comes from.
//
// The full basis (bands, retailer classes, verify-with search terms, review
// log) ships as an asset: assets/PRICE_SOURCES.md. Keep the two in sync —
// changing a price in the catalog means updating that table too.

class PriceSources {
  PriceSources._();

  /// Bundled document with the complete table.
  static const assetPath = 'assets/PRICE_SOURCES.md';

  /// Short label shown next to every price.
  static const estimatePrefix = 'est.';

  /// One-line basis shown under a price on inspect.
  static const generalBasis =
      'PH mid-market retail, 2025 · ±30% · not a quote';

  /// Per-item retailer hint, keyed by catalog baseId / preset furniture id.
  static const Map<String, String> _byId = {
    'desk': 'Lazada/Shopee, SM Home, IKEA PH',
    'gaming_desk': 'Fantech / Rakk stores, Secretlab PH',
    'chair': 'Lazada/Shopee, Our Home, IKEA PH',
    'pc': 'DynaQuest, PCHub, EasyPC builds',
    'bed': 'Mandaue Foam, Uratex, SM Home',
    'sofa': 'Mandaue Foam, SM Home, Our Home',
    'table': 'SM Home, IKEA PH',
    'wardrobe': 'SM Home, Our Home',
    'shelf': 'IKEA PH, Lazada/Shopee',
    'bookshelf': 'IKEA PH, Lazada/Shopee',
    'plant': 'Plant markets, SM Home',
    'tv': 'Abenson, SM Appliance, Xiaomi PH',
    'door': 'Wilcon Depot, AllHome',
    'window': 'Wilcon Depot, glass & aluminium shops',
    'ac': 'Abenson, SM Appliance (Carrier/Condura/Kolin)',
    'intake_vent': 'Wilcon Depot, Lazada/Shopee',
    'exhaust_fan': 'Abenson, Wilcon (Asahi/Hanabishi)',
    'portable_ac': 'Abenson, SM Appliance',
    'fan': 'Abenson (Asahi/Hanabishi/Union)',
    'space_heater': 'Lazada/Shopee, Abenson',
    'lamp': 'Firefly/Omni/Xiaomi PH, IKEA PH',
    'floor_lamp': 'IKEA PH, SM Home',
    'ceiling_light': 'Wilcon Depot (Firefly/Omni)',
    'purifier': 'Xiaomi PH, Abenson',
    'monitor': 'Abenson, AOC/Nvision/Xiaomi stores',
    'upg_fan': 'Abenson, Lazada/Shopee',
    'upg_purifier': 'Xiaomi PH, Abenson',
    'upg_floor_lamp': 'IKEA PH, SM Home',
    'upg_blinds': 'Aqara / SwitchBot PH, blinds shops',
  };

  /// Hint for an item id (strips catalog suffixes like `desk_2`).
  static String? hintFor(String id) {
    if (_byId.containsKey(id)) return _byId[id];
    final base = id.replaceFirst(RegExp(r'_\d+$'), '');
    return _byId[base];
  }

  /// `est. ₱4,500` style label.
  static String estimateLabel(String formattedAmount) =>
      '$estimatePrefix $formattedAmount';
}
