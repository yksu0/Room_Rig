import 'scan_pipeline.dart';

/// Web / desktop-chrome: TFLite + dart:ffi are unavailable.
class TfliteObjectDetector implements ObjectDetector {
  final String modelAssetPath;
  final double scoreThreshold;
  final double iouThreshold;
  final int maxDetections;
  final List<String> classLabels;

  TfliteObjectDetector({
    required this.modelAssetPath,
    this.scoreThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.maxDetections = 12,
    this.classLabels = const [],
  });

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async => const [];
}

/// Compat alias for older call sites.
typedef TfliteObjectDetectorPlaceholder = TfliteObjectDetector;
