import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/scan_layout_model.dart';
import 'scan_pipeline.dart';

class ArCoreTrackingProviderStub implements TrackingProvider {
  static const _channelName = 'room_rig/arcore';
  static const MethodChannel _channel = MethodChannel(_channelName);

  int _frameIndex = 0;
  bool _nativeReady = false;

  @override
  Future<void> initialize() async {
    _frameIndex = 0;
    _nativeReady = false;

    if (!defaultTargetPlatform.name.toLowerCase().contains('android')) {
      return;
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('initializeTracking');
      _nativeReady = (result?['ready'] as bool?) ?? false;
    } catch (_) {
      _nativeReady = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_nativeReady) return;
    try {
      await _channel.invokeMethod<void>('disposeTracking');
    } catch (_) {
      // Ignore and allow fallback path on next session.
    }
    _nativeReady = false;
  }

  @override
  Future<TrackingSample> update(ScanFrameInput frame) async {
    if (_nativeReady) {
      try {
        final result = await _channel.invokeMethod<Map<Object?, Object?>>(
          'updateTracking',
          {'timestampMs': frame.timestamp.millisecondsSinceEpoch},
        );

        if (result != null) {
          return TrackingSample(
            cameraPosition: Vec3(
              x: (result['x'] as num?)?.toDouble() ?? 0,
              y: (result['y'] as num?)?.toDouble() ?? 0,
              z: (result['z'] as num?)?.toDouble() ?? 0,
            ),
            cameraEulerDegrees: Vec3(
              x: (result['pitch'] as num?)?.toDouble() ?? 0,
              y: (result['yaw'] as num?)?.toDouble() ?? 0,
              z: (result['roll'] as num?)?.toDouble() ?? 0,
            ),
            trackingStable: (result['trackingStable'] as bool?) ?? true,
          );
        }
      } catch (_) {
        _nativeReady = false;
      }
    }

    // Fallback simulated tracking when native channel is unavailable.
    _frameIndex++;
    final t = _frameIndex / 16.0;

    return TrackingSample(
      cameraPosition: Vec3(
        x: 1.2 + sin(t) * 0.9,
        y: 1.5,
        z: 1.1 + cos(t * 0.8) * 0.9,
      ),
      cameraEulerDegrees: Vec3(
        x: 0,
        y: (t * 25) % 360,
        z: 0,
      ),
      trackingStable: true,
    );
  }
}

class BasicFrameQualityAnalyzer implements FrameQualityAnalyzer {
  @override
  Future<ScanQualityReport> analyze(ScanFrameInput frame) async {
    if (frame.bytes.isEmpty) {
      return const ScanQualityReport(
        acceptable: false,
        issues: [ScanQualityIssue.lowTexture, ScanQualityIssue.poorLighting],
      );
    }

    final sampleStride = max(1, frame.bytes.length ~/ 800);
    int sampleCount = 0;
    double brightnessSum = 0;
    double contrastAccumulator = 0;
    int previous = frame.bytes.first;

    for (int i = 0; i < frame.bytes.length; i += sampleStride) {
      final pixel = frame.bytes[i];
      brightnessSum += pixel;
      contrastAccumulator += (pixel - previous).abs();
      previous = pixel;
      sampleCount++;
    }

    final avgBrightness = brightnessSum / max(1, sampleCount);
    final avgContrast = contrastAccumulator / max(1, sampleCount);

    final issues = <ScanQualityIssue>[];
    if (avgBrightness < 35) {
      issues.add(ScanQualityIssue.poorLighting);
    }
    if (avgContrast < 12) {
      issues.add(ScanQualityIssue.motionBlur);
    }
    if (avgContrast < 8) {
      issues.add(ScanQualityIssue.lowTexture);
    }

    return ScanQualityReport(acceptable: issues.length < 2, issues: issues);
  }
}

class HeuristicObjectDetector implements ObjectDetector {
  int _frameIndex = 0;

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    _frameIndex++;
    if (_frameIndex % 6 != 0) {
      return const [];
    }

    final hash = (frame.timestamp.microsecondsSinceEpoch ~/ 10000) % 3;
    switch (hash) {
      case 0:
        return const [
          Detection2D(
            label: 'Desk',
            category: 'ergonomics',
            confidence: 0.82,
            left: 0.20,
            top: 0.36,
            width: 0.28,
            height: 0.16,
          ),
        ];
      case 1:
        return const [
          Detection2D(
            label: 'Chair',
            category: 'ergonomics',
            confidence: 0.80,
            left: 0.52,
            top: 0.48,
            width: 0.18,
            height: 0.20,
          ),
        ];
      default:
        return const [
          Detection2D(
            label: 'Window',
            category: 'lighting',
            confidence: 0.86,
            left: 0.62,
            top: 0.18,
            width: 0.25,
            height: 0.22,
          ),
        ];
    }
  }
}

class TfliteObjectDetectorPlaceholder implements ObjectDetector {
  final String modelAssetPath;
  final double scoreThreshold;
  final double iouThreshold;
  final int maxDetections;
  final List<String> classLabels;

  bool _initAttempted = false;
  Interpreter? _interpreter;
  int _inputWidth = 640;
  int _inputHeight = 640;
  bool _inputIsNhwc = true;

  TfliteObjectDetectorPlaceholder({
    required this.modelAssetPath,
    this.scoreThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.maxDetections = 12,
    this.classLabels = const [
      'chair',
      'desk',
      'sofa',
      'bed',
      'table',
      'monitor',
      'tv',
      'lamp',
      'window',
      'door',
      'shelf',
      'cabinet',
      'fan',
      'plant',
      'ac',
    ],
  });

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    await _ensureInterpreter();
    final interpreter = _interpreter;
    if (interpreter == null) {
      return const [];
    }

    if (frame.bytes.isEmpty) {
      return const [];
    }

    try {
      final input = _buildInputTensor(frame.bytes);
      final outputTensor = interpreter.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      final output = _createZeros(outputShape);

      interpreter.run(input, output);

      return YoloLikePostProcessor.decode(
        rawOutput: output,
        outputShape: outputShape,
        labels: classLabels,
        inputWidth: _inputWidth,
        inputHeight: _inputHeight,
        scoreThreshold: scoreThreshold,
        iouThreshold: iouThreshold,
        maxDetections: maxDetections,
      );
    } catch (_) {
      // Let HybridObjectDetector fallback path handle failures.
      return const [];
    }
  }

  Future<void> _ensureInterpreter() async {
    if (_initAttempted) return;
    _initAttempted = true;

    try {
      await rootBundle.load(modelAssetPath);

      final options = InterpreterOptions()..threads = 2;
      final interpreter = await Interpreter.fromAsset(modelAssetPath, options: options);

      final inputTensor = interpreter.getInputTensor(0);
      final shape = inputTensor.shape;
      if (shape.length == 4) {
        if (shape[3] == 3) {
          _inputIsNhwc = true;
          _inputHeight = shape[1];
          _inputWidth = shape[2];
        } else if (shape[1] == 3) {
          _inputIsNhwc = false;
          _inputHeight = shape[2];
          _inputWidth = shape[3];
        }
      }

      _interpreter = interpreter;
    } catch (_) {
      _interpreter = null;
    }
  }

  dynamic _buildInputTensor(List<int> lumaBytes) {
    if (_inputIsNhwc) {
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (y) => List.generate(_inputWidth, (x) {
            final pixel = _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight) / 255.0;
            return <double>[pixel, pixel, pixel];
          }),
        ),
      );
      return input;
    }

    final input = List.generate(
      1,
      (_) => List.generate(
        3,
        (_) => List.generate(_inputHeight, (y) {
          return List.generate(_inputWidth, (x) {
            final pixel = _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight) / 255.0;
            return pixel;
          });
        }),
      ),
    );
    return input;
  }

  int _sampleLuma(List<int> bytes, int x, int y, int width, int height) {
    final srcX = (x * (sqrt(bytes.length).toInt().clamp(1, width)) / max(1, width)).floor();
    final srcY = (y * (sqrt(bytes.length).toInt().clamp(1, height)) / max(1, height)).floor();
    final srcW = sqrt(bytes.length).toInt().clamp(1, bytes.length);
    final idx = (srcY * srcW + srcX).clamp(0, bytes.length - 1);
    return bytes[idx];
  }

  dynamic _createZeros(List<int> shape) {
    if (shape.isEmpty) {
      return 0.0;
    }
    if (shape.length == 1) {
      return List<double>.filled(shape.first, 0.0);
    }
    return List.generate(shape.first, (_) => _createZeros(shape.sublist(1)));
  }
}

class YoloLikePostProcessor {
  static List<Detection2D> decode({
    required dynamic rawOutput,
    required List<int> outputShape,
    required List<String> labels,
    required int inputWidth,
    required int inputHeight,
    required double scoreThreshold,
    required double iouThreshold,
    required int maxDetections,
  }) {
    final candidates = _toCandidates(rawOutput, outputShape);
    if (candidates.isEmpty) {
      return const [];
    }

    final detections = <_DecodedCandidate>[];
    for (final row in candidates) {
      if (row.length < 6) continue;

      final cx = row[0];
      final cy = row[1];
      final w = row[2].abs();
      final h = row[3].abs();

      bool hasObj = false;
      if (row.length >= 6) {
        final obj = row[4];
        hasObj = obj >= 0 && obj <= 1;
      }

      final classOffset = hasObj ? 5 : 4;
      if (classOffset >= row.length) continue;

      var bestClass = 0;
      var bestClassScore = 0.0;
      for (int i = classOffset; i < row.length; i++) {
        final s = row[i];
        if (s > bestClassScore) {
          bestClassScore = s;
          bestClass = i - classOffset;
        }
      }

      final conf = hasObj ? (row[4] * bestClassScore) : bestClassScore;
      if (conf < scoreThreshold) continue;

      final normCx = cx > 1.5 ? cx / inputWidth : cx;
      final normCy = cy > 1.5 ? cy / inputHeight : cy;
      final normW = w > 1.5 ? w / inputWidth : w;
      final normH = h > 1.5 ? h / inputHeight : h;

      final left = (normCx - normW / 2).clamp(0.0, 1.0);
      final top = (normCy - normH / 2).clamp(0.0, 1.0);
      final width = normW.clamp(0.0, 1.0);
      final height = normH.clamp(0.0, 1.0);

      detections.add(
        _DecodedCandidate(
          classIndex: bestClass,
          score: conf,
          left: left,
          top: top,
          width: width,
          height: height,
        ),
      );
    }

    final selected = _nms(detections, iouThreshold, maxDetections);
    return selected
        .map((d) {
          final label = (d.classIndex >= 0 && d.classIndex < labels.length)
              ? labels[d.classIndex]
              : 'object_${d.classIndex}';
          return Detection2D(
            label: _formatLabel(label),
            category: _mapCategory(label),
            confidence: d.score.clamp(0.0, 1.0),
            left: d.left,
            top: d.top,
            width: d.width,
            height: d.height,
          );
        })
        .toList(growable: false);
  }

  static List<List<double>> _toCandidates(dynamic output, List<int> shape) {
    if (shape.length != 3 || shape.first != 1) {
      return const [];
    }

    final flat = <double>[];
    _flatten(output, flat);
    if (flat.isEmpty) return const [];

    final a = shape[1];
    final b = shape[2];

    final rows = <List<double>>[];
    final featuresFirst = (a >= 6 && b < 6) ||
        (a >= 6 && b >= 6 && b >= a);

    if (featuresFirst) {
      // [1, features, count]
      for (int c = 0; c < b; c++) {
        final row = List<double>.filled(a, 0.0);
        for (int f = 0; f < a; f++) {
          row[f] = flat[f * b + c];
        }
        rows.add(row);
      }
      return rows;
    }

    if (b >= 6) {
      // [1, count, features]
      for (int c = 0; c < a; c++) {
        final row = List<double>.filled(b, 0.0);
        for (int f = 0; f < b; f++) {
          row[f] = flat[c * b + f];
        }
        rows.add(row);
      }
      return rows;
    }

    return const [];
  }

  static void _flatten(dynamic value, List<double> out) {
    if (value is List) {
      for (final v in value) {
        _flatten(v, out);
      }
      return;
    }
    if (value is num) {
      out.add(value.toDouble());
    }
  }

  static List<_DecodedCandidate> _nms(
    List<_DecodedCandidate> detections,
    double iouThreshold,
    int maxDetections,
  ) {
    detections.sort((a, b) => b.score.compareTo(a.score));
    final selected = <_DecodedCandidate>[];

    for (final d in detections) {
      var shouldKeep = true;
      for (final s in selected) {
        if (d.classIndex != s.classIndex) continue;
        if (_iou(d, s) > iouThreshold) {
          shouldKeep = false;
          break;
        }
      }
      if (shouldKeep) {
        selected.add(d);
        if (selected.length >= maxDetections) break;
      }
    }

    return selected;
  }

  static double _iou(_DecodedCandidate a, _DecodedCandidate b) {
    final ax2 = a.left + a.width;
    final ay2 = a.top + a.height;
    final bx2 = b.left + b.width;
    final by2 = b.top + b.height;

    final ix1 = max(a.left, b.left);
    final iy1 = max(a.top, b.top);
    final ix2 = min(ax2, bx2);
    final iy2 = min(ay2, by2);

    final iw = max(0.0, ix2 - ix1);
    final ih = max(0.0, iy2 - iy1);
    final inter = iw * ih;
    if (inter <= 0) return 0;

    final union = (a.width * a.height) + (b.width * b.height) - inter;
    if (union <= 0) return 0;
    return inter / union;
  }

  static String _formatLabel(String raw) {
    if (raw.isEmpty) return 'Object';
    final clean = raw.replaceAll('_', ' ').trim();
    return clean[0].toUpperCase() + clean.substring(1);
  }

  static String _mapCategory(String label) {
    final v = label.toLowerCase();
    if (v.contains('chair') || v.contains('desk') || v.contains('table') || v.contains('sofa') || v.contains('bed')) {
      return 'ergonomics';
    }
    if (v.contains('window') || v.contains('lamp') || v.contains('light') || v.contains('monitor') || v.contains('tv')) {
      return 'lighting';
    }
    if (v.contains('fan') || v.contains('ac') || v.contains('vent') || v.contains('air')) {
      return 'airflow';
    }
    return 'neutral';
  }
}

class _DecodedCandidate {
  final int classIndex;
  final double score;
  final double left;
  final double top;
  final double width;
  final double height;

  const _DecodedCandidate({
    required this.classIndex,
    required this.score,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class HybridObjectDetector implements ObjectDetector {
  final ObjectDetector primary;
  final ObjectDetector fallback;

  const HybridObjectDetector({required this.primary, required this.fallback});

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    final primaryResults = await primary.detect(frame);
    if (primaryResults.isNotEmpty) {
      return primaryResults;
    }
    return fallback.detect(frame);
  }
}

class GridCoverageFusionEngine implements ScanFusionEngine {
  static const double _staleDecayPerFrame = 0.035;
  static const double _minConfidenceToKeep = 0.18;

  @override
  ScanFusionState initialize(RoomLayoutModel seedLayout) {
    return ScanFusionState(layout: seedLayout);
  }

  @override
  ScanFusionState fuseFrame({
    required ScanFusionState current,
    required ScanFrameResult frame,
  }) {
    final layout = current.layout;
    final grid = layout.coverageGrid;

    if (grid.cols == 0 || grid.rows == 0) {
      return current;
    }

    final nx = (frame.tracking.cameraPosition.x / max(0.001, layout.dimensions.lengthMeters)).clamp(0.0, 0.9999);
    final nz = (frame.tracking.cameraPosition.z / max(0.001, layout.dimensions.widthMeters)).clamp(0.0, 0.9999);

    final col = (nx * grid.cols).floor().clamp(0, grid.cols - 1);
    final row = (nz * grid.rows).floor().clamp(0, grid.rows - 1);

    var nextGrid = grid.markCell(col, row, 1.0);

    final localBoost = frame.quality.acceptable ? 0.75 : 0.45;
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        nextGrid = nextGrid.markCell(col + dx, row + dy, localBoost);
      }
    }

    for (final d in frame.detections) {
      final dCol = (d.left * grid.cols).floor().clamp(0, grid.cols - 1);
      final dRow = (d.top * grid.rows).floor().clamp(0, grid.rows - 1);
      nextGrid = nextGrid.markCell(dCol, dRow, 1.0);
    }

    final nextObjects = _fuseObjects(
      currentObjects: layout.objects,
      detections: frame.detections,
      tracking: frame.tracking,
      dimensions: layout.dimensions,
    );

    return ScanFusionState(layout: layout.withCoverage(nextGrid).withObjects(nextObjects));
  }

  @override
  RoomLayoutModel finalize(ScanFusionState state) {
    return state.layout;
  }

  List<ScanObject> _fuseObjects({
    required List<ScanObject> currentObjects,
    required List<Detection2D> detections,
    required TrackingSample tracking,
    required RoomDimensions dimensions,
  }) {
    final next = List<ScanObject>.from(currentObjects);
    final updatedIndices = <int>{};

    for (final det in detections) {
      final candidate = _estimateObject(det, tracking, dimensions);

      int bestIndex = -1;
      double bestDist = 1.25;
      for (int i = 0; i < next.length; i++) {
        final obj = next[i];
        if (obj.label.toLowerCase() != candidate.label.toLowerCase()) continue;
        final dist = _distanceMeters(obj.center, candidate.center);
        if (dist < bestDist) {
          bestDist = dist;
          bestIndex = i;
        }
      }

      if (bestIndex >= 0) {
        final existing = next[bestIndex];
        if (existing.locked) {
          updatedIndices.add(bestIndex);
          continue;
        }
        next[bestIndex] = existing.copyWith(
          center: Vec3.lerp(existing.center, candidate.center, 0.35),
          sizeMeters: Vec3.lerp(existing.sizeMeters, candidate.sizeMeters, 0.30),
          confidence: (existing.confidence * 0.65 + candidate.confidence * 0.35).clamp(0, 1).toDouble(),
          yawDegrees: candidate.yawDegrees,
        );
        updatedIndices.add(bestIndex);
      } else {
        next.add(candidate);
        updatedIndices.add(next.length - 1);
      }
    }

    return _applyStaleDecayAndPruning(next, updatedIndices);
  }

  List<ScanObject> _applyStaleDecayAndPruning(
    List<ScanObject> objects,
    Set<int> updatedIndices,
  ) {
    final decayed = <ScanObject>[];

    for (int i = 0; i < objects.length; i++) {
      final obj = objects[i];

      if (obj.locked || obj.source != 'scan-fusion' || updatedIndices.contains(i)) {
        decayed.add(obj);
        continue;
      }

      final nextConfidence = (obj.confidence - _staleDecayPerFrame).clamp(0.0, 1.0).toDouble();
      if (nextConfidence < _minConfidenceToKeep) {
        continue;
      }

      decayed.add(obj.copyWith(confidence: nextConfidence));
    }

    return decayed;
  }

  ScanObject _estimateObject(Detection2D det, TrackingSample tracking, RoomDimensions dimensions) {
    final cxNorm = (det.left + det.width / 2).clamp(0.0, 1.0);
    final czNorm = (det.top + det.height / 2).clamp(0.0, 1.0);

    final worldX = ((cxNorm * dimensions.lengthMeters) * 0.7 + tracking.cameraPosition.x * 0.3)
        .clamp(0.0, dimensions.lengthMeters);
    final worldZ = ((czNorm * dimensions.widthMeters) * 0.7 + tracking.cameraPosition.z * 0.3)
        .clamp(0.0, dimensions.widthMeters);

    final estWidth = (det.width * dimensions.lengthMeters).clamp(0.25, 2.4);
    final estDepth = (det.height * dimensions.widthMeters).clamp(0.25, 2.4);
    final estHeight = ((det.height * dimensions.heightMeters) * 0.95).clamp(0.35, 2.2);

    final id = '${det.label.toLowerCase().replaceAll(' ', '_')}_${worldX.toStringAsFixed(1)}_${worldZ.toStringAsFixed(1)}';

    return ScanObject(
      id: id,
      label: det.label,
      category: det.category,
      confidence: det.confidence,
      center: Vec3(x: worldX, y: estHeight / 2, z: worldZ),
      sizeMeters: Vec3(x: estWidth, y: estHeight, z: estDepth),
      yawDegrees: tracking.cameraEulerDegrees.y,
      source: 'scan-fusion',
    );
  }

  double _distanceMeters(Vec3 a, Vec3 b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }
}
