import 'package:flutter/services.dart';

/// Whether the on-device YOLO model is bundled in assets — plus honest demo copy.
class ScanModelAvailability {
  ScanModelAvailability._();

  static const productionModelPath = 'assets/models/yolo_roomrig.tflite';
  static const labelsAssetPath = 'assets/models/yolo_roomrig_labels.txt';

  static bool? _cachedBundled;

  /// Drop cache after swapping the asset model (e.g. Colab TFLite install).
  static void clearCache() => _cachedBundled = null;

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
      try {
        final raw = await rootBundle.loadString(labelsAssetPath);
        final n = raw
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .length;
        if (n > 0 && n <= 30) {
          return 'Room Rig YOLO ($n classes)';
        }
        if (n >= 70) return 'COCO YOLO (smoke test)';
      } catch (_) {}
      return 'YOLO detector';
    }
    return 'Approximate / luma heuristics';
  }

  /// Human label for tracking backend.
  static String trackingLabel(String? source) {
    final s = (source ?? '').toLowerCase();
    if (s.contains('arcore') || s == 'native') return 'ARCore pose';
    if (s.contains('fused')) return 'ARCore+visual fuse';
    if (s.contains('visual')) return 'visual odometry (estimate)';
    if (s.contains('sim')) return 'simulated tracking';
    if (s.isEmpty) return 'tracking unknown';
    return source!;
  }

  /// One-line honesty strip shown on Scan (idle + live).
  ///
  /// [roomSizeSource]: `preset` | `measured` | `manual` | `object-scale`.
  /// [trackingSource]: raw TrackingSample.source or backend id.
  static Future<String> honestySummary({
    required bool usingHeuristicFallback,
    String roomSizeSource = 'preset',
    String? trackingSource,
  }) async {
    // Keep await so callers still refresh model cache / async contract.
    await detectorLabel(usingHeuristicFallback: usingHeuristicFallback);
    final sizeLabel = switch (roomSizeSource) {
      'measured' => 'AR-marked size',
      'manual' => 'manual room size',
      'object-scale' => 'object-scale size hint',
      _ => 'preset room size',
    };
    final track = trackingLabel(trackingSource);
    return 'Room measure · $sizeLabel · $track';
  }

  /// Longer bullets for the pre-scan sheet.
  static const honestyBullets = <String>[
    'Scan measures the room footprint (AR corner marks or manual L×W), then opens Rig empty.',
    'On Android, Prefer ARCore for lock + corner marks. Furniture comes from Rig — not live YOLO on this path.',
    'Blocked corners: mark the nearest visible wall base, then edit length × width on Confirm.',
    'Primary product loop is Hub → Rig → Bench → Upgrades; Scan only seeds room size.',
  ];
}
