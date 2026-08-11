import '../models/item_detection.dart';
import '../models/scan_layout_model.dart';

enum ScanQualityIssue {
  lowTexture,
  motionBlur,
  poorLighting,
  trackingLost,
}

class ScanFrameInput {
  final DateTime timestamp;
  final int width;
  final int height;
  final List<int> bytes;

  /// When set (e.g. ARCore-owned capture), tracking skips a second native poll.
  final TrackingSample? attachedTracking;

  const ScanFrameInput({
    required this.timestamp,
    required this.width,
    required this.height,
    required this.bytes,
    this.attachedTracking,
  });
}

class TrackingSample {
  final Vec3 cameraPosition;
  final Vec3 cameraEulerDegrees;
  final bool trackingStable;
  final double confidence;
  final String source;
  final double motionMeters;
  final double? depthHintMeters;

  const TrackingSample({
    required this.cameraPosition,
    required this.cameraEulerDegrees,
    required this.trackingStable,
    this.confidence = 0.7,
    this.source = 'unknown',
    this.motionMeters = 0,
    this.depthHintMeters,
  });
}

class ScanQualityReport {
  final bool acceptable;
  final List<ScanQualityIssue> issues;

  const ScanQualityReport({required this.acceptable, required this.issues});
}

class Detection2D {
  final String label;
  final String category;
  final double confidence;
  final double left;
  final double top;
  final double width;
  final double height;

  const Detection2D({
    required this.label,
    required this.category,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  ItemDetection toItemDetection({required String id, required int sourceFrame}) {
    return ItemDetection(
      id: id,
      label: label,
      category: category,
      bbox: BBox2D(left: left, top: top, width: width, height: height),
      confidence: confidence,
      sourceFrame: sourceFrame,
    );
  }
}

class ScanFrameResult {
  final TrackingSample tracking;
  final ScanQualityReport quality;
  final List<Detection2D> detections;

  const ScanFrameResult({
    required this.tracking,
    required this.quality,
    required this.detections,
  });
}

abstract class TrackingProvider {
  Future<void> initialize();
  Future<void> dispose();
  Future<TrackingSample> update(ScanFrameInput frame);
}

abstract class FrameQualityAnalyzer {
  Future<ScanQualityReport> analyze(ScanFrameInput frame);
}

abstract class ObjectDetector {
  Future<List<Detection2D>> detect(ScanFrameInput frame);
}

class ScanFusionState {
  final RoomLayoutModel layout;

  const ScanFusionState({required this.layout});
}

abstract class ScanFusionEngine {
  ScanFusionState initialize(RoomLayoutModel seedLayout);

  ScanFusionState fuseFrame({
    required ScanFusionState current,
    required ScanFrameResult frame,
  });

  RoomLayoutModel finalize(ScanFusionState state);
}

class ScanPipeline {
  final TrackingProvider trackingProvider;
  final FrameQualityAnalyzer qualityAnalyzer;
  final ObjectDetector objectDetector;
  final ScanFusionEngine fusionEngine;

  ScanFusionState? _state;
  TrackingSample? _lastTrackingSample;

  ScanPipeline({
    required this.trackingProvider,
    required this.qualityAnalyzer,
    required this.objectDetector,
    required this.fusionEngine,
  });

  Future<void> initialize(RoomLayoutModel seedLayout) async {
    await trackingProvider.initialize();
    _state = fusionEngine.initialize(seedLayout);
  }

  Future<ScanPipelineTick> processFrame(ScanFrameInput frame) async {
    final current = _state;
    if (current == null) {
      throw StateError('ScanPipeline must be initialized before processing frames.');
    }

    var trackingFallbackUsed = false;
    var qualityFallbackUsed = false;
    var detectorFallbackUsed = false;
    var fusionFallbackUsed = false;

    TrackingSample tracking;
    try {
      tracking = await trackingProvider.update(frame);
      _lastTrackingSample = tracking;
    } catch (_) {
      trackingFallbackUsed = true;
      tracking = _lastTrackingSample ??
          const TrackingSample(
            cameraPosition: Vec3(x: 0, y: 1.5, z: 0),
            cameraEulerDegrees: Vec3(x: 0, y: 0, z: 0),
            trackingStable: false,
          );
    }

    ScanQualityReport baseQuality;
    try {
      baseQuality = await qualityAnalyzer.analyze(frame);
    } catch (_) {
      qualityFallbackUsed = true;
      baseQuality = const ScanQualityReport(
        acceptable: false,
        issues: [ScanQualityIssue.lowTexture],
      );
    }

    final quality = _mergeTrackingQuality(baseQuality, tracking);

    List<Detection2D> detections;
    try {
      detections = await objectDetector.detect(frame);
    } catch (_) {
      detectorFallbackUsed = true;
      detections = const [];
    }

    final result = ScanFrameResult(
      tracking: tracking,
      quality: quality,
      detections: detections,
    );

    ScanFusionState next;
    try {
      next = fusionEngine.fuseFrame(current: current, frame: result);
    } catch (_) {
      fusionFallbackUsed = true;
      next = current;
    }

    _state = next;
    return ScanPipelineTick(
      layout: next.layout,
      frameResult: result,
      diagnostics: ScanPipelineDiagnostics(
        trackingFallbackUsed: trackingFallbackUsed || tracking.source == 'simulated' || tracking.source == 'fallback',
        qualityFallbackUsed: qualityFallbackUsed,
        detectorFallbackUsed: detectorFallbackUsed,
        fusionFallbackUsed: fusionFallbackUsed,
        trackingSource: tracking.source,
        trackingConfidence: tracking.confidence,
      ),
    );
  }

  ScanQualityReport _mergeTrackingQuality(
    ScanQualityReport base,
    TrackingSample tracking,
  ) {
    final mergedIssues = <ScanQualityIssue>[...base.issues];
    if (!tracking.trackingStable || tracking.confidence < 0.35) {
      if (!mergedIssues.contains(ScanQualityIssue.trackingLost)) {
        mergedIssues.add(ScanQualityIssue.trackingLost);
      }
    }
    if (tracking.motionMeters > 0.35) {
      if (!mergedIssues.contains(ScanQualityIssue.motionBlur)) {
        mergedIssues.add(ScanQualityIssue.motionBlur);
      }
    }

    final trackingOk = tracking.trackingStable && tracking.confidence >= 0.35;
    final acceptable = trackingOk && base.acceptable && mergedIssues.length < 2;
    return ScanQualityReport(acceptable: acceptable, issues: mergedIssues);
  }

  RoomLayoutModel finalize() {
    final current = _state;
    if (current == null) {
      throw StateError('ScanPipeline must be initialized before finalize.');
    }
    return fusionEngine.finalize(current);
  }

  Future<void> dispose() async {
    await trackingProvider.dispose();
  }
}

class ScanPipelineTick {
  final RoomLayoutModel layout;
  final ScanFrameResult frameResult;
  final ScanPipelineDiagnostics diagnostics;

  const ScanPipelineTick({
    required this.layout,
    required this.frameResult,
    this.diagnostics = const ScanPipelineDiagnostics(),
  });
}

class ScanPipelineDiagnostics {
  final bool trackingFallbackUsed;
  final bool qualityFallbackUsed;
  final bool detectorFallbackUsed;
  final bool fusionFallbackUsed;
  final String trackingSource;
  final double trackingConfidence;

  const ScanPipelineDiagnostics({
    this.trackingFallbackUsed = false,
    this.qualityFallbackUsed = false,
    this.detectorFallbackUsed = false,
    this.fusionFallbackUsed = false,
    this.trackingSource = 'unknown',
    this.trackingConfidence = 0,
  });

  bool get hasFallback =>
      trackingFallbackUsed || qualityFallbackUsed || detectorFallbackUsed || fusionFallbackUsed;
}
