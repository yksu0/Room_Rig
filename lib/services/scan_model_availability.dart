import 'package:flutter/services.dart';

/// Whether the on-device YOLO model is bundled in assets — plus honest demo copy.
class ScanModelAvailability {
  ScanModelAvailability._();

  static const productionModelPath = 'assets/models/yolo_roomrig.tflite';
  static const labelsAssetPath = 'assets/models/yolo_roomrig_labels.txt';

  static bool? _cachedBundled;

  /// True when [productionModelPath] exists in the asset bundle.
  static Future<bool> isProductionModelBundled() async {
    if (_cachedBundled != null) return _cachedBundled!;
    try {
      await rootBundle.load(productionModelPath);
      _cachedBundled = true;
    } catch (_) {
      _cachedBundled = false;
    }
    return _cachedBundled!;
  }

  /// Short chip label for the active detector path.
  static Future<String> detectorLabel({required bool usingHeuristicFallback}) async {
    if (await isProductionModelBundled() && !usingHeuristicFallback) {
      return 'COCO YOLO (smoke test)';
    }
    return 'Approximate / luma heuristics';
  }

  /// One-line honesty strip shown on Scan (idle + live).
  ///
  /// [roomSizeSource]: `preset` | `measured` | `object-scale`.
  static Future<String> honestySummary({
    required bool usingHeuristicFallback,
    String roomSizeSource = 'preset',
  }) async {
    final detector = await detectorLabel(usingHeuristicFallback: usingHeuristicFallback);
    final sizeLabel = switch (roomSizeSource) {
      'measured' => 'walk-measured size',
      'object-scale' => 'object-scale size hint',
      _ => 'preset room size',
    };
    return '$detector · $sizeLabel · visual tracking (not SLAM)';
  }

  /// Longer bullets for the pre-scan sheet.
  static const honestyBullets = <String>[
    'Room size usually uses the active Hub preset; walk-to-measure runs when ARCore owns the camera.',
    'Object-scale can nudge dimensions from known pieces (bed/sofa/chair) when confidence is high — still approximate.',
    'Position on the minimap is visual tracking, not full AR SLAM.',
    'Detection may use a COCO YOLO smoke model (mapped into Rig icons) or luma heuristics — not a custom Room Rig network yet.',
    'Primary product loop is Hub → Rig → Bench → Upgrades; Scan seeds a layout when it works.',
  ];
}
