import 'package:flutter/services.dart';

/// Whether the on-device YOLO model is bundled in assets.
class ScanModelAvailability {
  ScanModelAvailability._();

  static const productionModelPath = 'assets/models/yolo_roomrig.tflite';

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

  /// User-facing label for the active detector path.
  static Future<String> detectorLabel({required bool usingHeuristicFallback}) async {
    if (await isProductionModelBundled() && !usingHeuristicFallback) {
      return 'YOLO room detector';
    }
    return 'Approximate layout scan';
  }
}
