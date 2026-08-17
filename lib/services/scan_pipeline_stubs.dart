import 'dart:math';

import '../models/item_detection.dart';
import '../models/scan_layout_model.dart';
import 'scan_layout_converter.dart';
import 'scan_pipeline.dart';

// Tracking providers live in scan_tracking.dart (Composite + visual odometry).
export 'scan_tracking.dart';

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
    if (avgContrast < 10) {
      issues.add(ScanQualityIssue.lowTexture);
    }

    final acceptable = issues.isEmpty ||
        (issues.length == 1 && issues.contains(ScanQualityIssue.lowTexture));
    return ScanQualityReport(acceptable: acceptable, issues: issues);
  }
}

class HeuristicObjectDetector implements ObjectDetector {
  final ObjectDetector _inner = LumaStructureObjectDetector();

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) {
    return _inner.detect(frame);
  }
}

/// Finds high-contrast structure in luma frames and maps blobs to room labels.
/// Used when a TFLite model is missing or returns no boxes (typical on S10+ until a model is shipped).
class LumaStructureObjectDetector implements ObjectDetector {
  static const _grid = 8;
  int _frameIndex = 0;
  List<Detection2D> _last = const [];

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    _frameIndex++;
    if (frame.bytes.isEmpty || frame.width <= 0 || frame.height <= 0) {
      return _last;
    }

    // Keep boxes sticky between frames so fusion can accumulate.
    if (_frameIndex % 3 != 0 && _last.isNotEmpty) {
      return _last;
    }

    final w = frame.width;
    final h = frame.height;
    final bw = max(1, w ~/ _grid);
    final bh = max(1, h ~/ _grid);
    final energy = List<double>.filled(_grid * _grid, 0);
    final brightness = List<double>.filled(_grid * _grid, 0);

    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        final x0 = gx * bw;
        final y0 = gy * bh;
        final x1 = min(w, x0 + bw);
        final y1 = min(h, y0 + bh);
        var sum = 0.0;
        var sumSq = 0.0;
        var n = 0;
        for (int y = y0; y < y1; y += 2) {
          for (int x = x0; x < x1; x += 2) {
            final idx = y * w + x;
            if (idx >= frame.bytes.length) continue;
            final v = frame.bytes[idx].toDouble();
            sum += v;
            sumSq += v * v;
            n++;
          }
        }
        final mean = n == 0 ? 0.0 : sum / n;
        final variance = n == 0 ? 0.0 : max(0.0, (sumSq / n) - mean * mean);
        final i = gy * _grid + gx;
        energy[i] = sqrt(variance);
        brightness[i] = mean;
      }
    }

    final threshold = _adaptiveThreshold(energy);
    final visited = List<bool>.filled(energy.length, false);
    final detections = <Detection2D>[];

    for (int i = 0; i < energy.length; i++) {
      if (visited[i] || energy[i] < threshold) continue;
      final cluster = <int>[];
      _flood(i, energy, threshold, visited, cluster);
      if (cluster.length < 3) continue;

      var minX = _grid, minY = _grid, maxX = 0, maxY = 0;
      var avgBright = 0.0;
      var avgEnergy = 0.0;
      for (final c in cluster) {
        final cx = c % _grid;
        final cy = c ~/ _grid;
        minX = min(minX, cx);
        minY = min(minY, cy);
        maxX = max(maxX, cx);
        maxY = max(maxY, cy);
        avgBright += brightness[c];
        avgEnergy += energy[c];
      }
      avgBright /= cluster.length;
      avgEnergy /= cluster.length;

      final left = (minX / _grid).clamp(0.0, 0.92);
      final top = (minY / _grid).clamp(0.0, 0.92);
      final width = (((maxX - minX + 1) / _grid)).clamp(0.08, 1.0 - left);
      final height = (((maxY - minY + 1) / _grid)).clamp(0.08, 1.0 - top);
      final labeled = _stickyLabel(
        left: left,
        top: top,
        width: width,
        height: height,
        brightness: avgBright,
        energy: avgEnergy,
      );
      detections.add(
        Detection2D(
          label: labeled.$1,
          category: labeled.$2,
          confidence: (0.55 + (avgEnergy / 80.0).clamp(0.0, 0.35)).clamp(0.5, 0.92),
          left: left,
          top: top,
          width: width,
          height: height,
        ),
      );
      if (detections.length >= 3) break;
    }

    if (detections.isEmpty) {
      return _last;
    }

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    _last = detections.take(6).toList(growable: false);
    return _last;
  }

  double _adaptiveThreshold(List<double> energy) {
    final sorted = List<double>.from(energy)..sort();
    final p70 = sorted[(sorted.length * 0.70).floor().clamp(0, sorted.length - 1)];
    return max(12.0, p70 * 0.95);
  }

  void _flood(
    int start,
    List<double> energy,
    double threshold,
    List<bool> visited,
    List<int> out,
  ) {
    final stack = <int>[start];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (i < 0 || i >= energy.length || visited[i] || energy[i] < threshold) continue;
      visited[i] = true;
      out.add(i);
      final x = i % _grid;
      final y = i ~/ _grid;
      if (x > 0) stack.add(i - 1);
      if (x < _grid - 1) stack.add(i + 1);
      if (y > 0) stack.add(i - _grid);
      if (y < _grid - 1) stack.add(i + _grid);
    }
  }

  (String, String) _labelBlob({
    required double left,
    required double top,
    required double width,
    required double height,
    required double brightness,
    required double energy,
  }) {
    final cx = left + width / 2;
    final cy = top + height / 2;
    final area = width * height;

    if (top < 0.28 && brightness > 140 && height < 0.35) {
      return ('Window', 'lighting');
    }
    if (left < 0.12 && height > 0.28) {
      return ('Door', 'neutral');
    }
    if (rightish(cx) && cy < 0.45 && brightness > 120) {
      return ('Lamp', 'lighting');
    }
    if (cy > 0.42 && area > 0.06 && width > height) {
      return ('Desk', 'ergonomics');
    }
    if (cy > 0.48 && area > 0.04 && height >= width * 0.85) {
      return ('Chair', 'ergonomics');
    }
    if (area > 0.12 && cy > 0.35) {
      return ('Sofa', 'ergonomics');
    }
    if (energy > 28 && cy < 0.5) {
      return ('Monitor', 'ergonomics');
    }
    return ('Desk', 'ergonomics');
  }

  (String, String) _stickyLabel({
    required double left,
    required double top,
    required double width,
    required double height,
    required double brightness,
    required double energy,
  }) {
    final fresh = _labelBlob(
      left: left,
      top: top,
      width: width,
      height: height,
      brightness: brightness,
      energy: energy,
    );
    final cx = left + width / 2;
    final cy = top + height / 2;
    for (final prev in _last) {
      final px = prev.left + prev.width / 2;
      final py = prev.top + prev.height / 2;
      final overlap = (cx - px).abs() < 0.22 && (cy - py).abs() < 0.22;
      if (overlap) {
        return (prev.label, prev.category);
      }
    }
    return fresh;
  }

  bool rightish(double cx) => cx > 0.62;
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
  static const double _staleDecayPerFrame = 0.012;
  static const double _minConfidenceToKeep = 0.16;
  int _frameIndex = 0;
  Vec3? _poseOrigin;
  Vec3? _seedOrigin;

  /// Pin the room origin to a measured world point (center of the size-walk).
  void useWorldOrigin(Vec3 origin) {
    _seedOrigin = origin;
  }

  @override
  ScanFusionState initialize(RoomLayoutModel seedLayout) {
    _frameIndex = 0;
    _poseOrigin = _seedOrigin;
    return ScanFusionState(layout: seedLayout);
  }

  Vec3 _mapWorldPoint(Vec3 pose, RoomDimensions dimensions) {
    _poseOrigin ??= Vec3(x: pose.x, y: pose.y, z: pose.z);
    final x = (pose.x - _poseOrigin!.x) + dimensions.lengthMeters * 0.5;
    final z = (pose.z - _poseOrigin!.z) + dimensions.widthMeters * 0.5;
    return Vec3(
      x: x.clamp(0.15, dimensions.lengthMeters - 0.15),
      y: pose.y,
      z: z.clamp(0.15, dimensions.widthMeters - 0.15),
    );
  }

  TrackingSample _mappedTracking(TrackingSample tracking, RoomDimensions dimensions) {
    final mapped = _mapWorldPoint(tracking.cameraPosition, dimensions);
    final look = tracking.lookAtPosition;
    return TrackingSample(
      cameraPosition: mapped,
      cameraEulerDegrees: tracking.cameraEulerDegrees,
      trackingStable: tracking.trackingStable,
      confidence: tracking.confidence,
      source: tracking.source,
      motionMeters: tracking.motionMeters,
      depthHintMeters: tracking.depthHintMeters,
      lookAtPosition: look == null ? null : _mapWorldPoint(look, dimensions),
      hasFloorHit: tracking.hasFloorHit,
    );
  }

  @override
  ScanFusionState fuseFrame({
    required ScanFusionState current,
    required ScanFrameResult frame,
  }) {
    final layout = current.layout;
    final grid = layout.coverageGrid;
    _frameIndex += 1;

    if (grid.cols == 0 || grid.rows == 0) {
      return current;
    }

    final tracking = _mappedTracking(frame.tracking, layout.dimensions);
    final aim = tracking.lookAtPosition ?? tracking.cameraPosition;
    final nx = (aim.x / max(0.001, layout.dimensions.lengthMeters)).clamp(0.0, 0.9999);
    final nz = (aim.z / max(0.001, layout.dimensions.widthMeters)).clamp(0.0, 0.9999);

    final col = (nx * grid.cols).floor().clamp(0, grid.cols - 1);
    final row = (nz * grid.rows).floor().clamp(0, grid.rows - 1);

    // Mark what the camera is looking at — not a wide blob under the user's feet.
    var nextGrid = grid.markCell(col, row, tracking.hasFloorHit || frame.quality.acceptable ? 1.0 : 0.45);
    if (frame.quality.acceptable) {
      nextGrid = nextGrid.markCell(col - 1, row, 0.55);
      nextGrid = nextGrid.markCell(col + 1, row, 0.55);
      nextGrid = nextGrid.markCell(col, row - 1, 0.55);
      nextGrid = nextGrid.markCell(col, row + 1, 0.55);
    }

    final nextObjects = _fuseObjects(
      currentObjects: layout.objects,
      detections: frame.detections,
      tracking: tracking,
      dimensions: layout.dimensions,
    );

    for (final obj in nextObjects) {
      final oCol = ((obj.center.x / max(0.001, layout.dimensions.lengthMeters)) * grid.cols)
          .floor()
          .clamp(0, grid.cols - 1);
      final oRow = ((obj.center.z / max(0.001, layout.dimensions.widthMeters)) * grid.rows)
          .floor()
          .clamp(0, grid.rows - 1);
      nextGrid = nextGrid.markCell(oCol, oRow, 1.0);
    }

    final itemDetections = <ItemDetection>[
      for (int i = 0; i < frame.detections.length; i++)
        frame.detections[i].toItemDetection(
          id: 'det_${_frameIndex}_$i',
          sourceFrame: _frameIndex,
        ),
    ];

    return ScanFusionState(
      layout: layout
          .withCoverage(nextGrid)
          .withObjects(nextObjects)
          .withDetections(itemDetections),
    );
  }

  @override
  RoomLayoutModel finalize(ScanFusionState state) {
    final layout = state.layout;
    final cols = layout.coverageGrid.cols;
    final rows = layout.coverageGrid.rows;
    if (cols <= 0 || rows <= 0) return layout;
    return ScanLayoutConverter.finalizeLayout(
      layout,
      gridCols: cols,
      gridRows: rows,
      inputProviderId: layout.scanSource ?? 'scan-fusion',
    );
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
      if (det.confidence < 0.55) continue;
      final candidate = _estimateObject(det, tracking, dimensions);

      int bestIndex = -1;
      double bestDist = 0.95;
      for (int i = 0; i < next.length; i++) {
        final obj = next[i];
        final sameLabel = obj.label.toLowerCase() == candidate.label.toLowerCase();
        final generic = obj.label.toLowerCase() == 'furniture' ||
            candidate.label.toLowerCase() == 'furniture';
        final dist = _distanceMeters(obj.center, candidate.center);
        final limit = sameLabel || generic ? 0.95 : 0.55;
        if (dist < limit && dist < bestDist) {
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
    final cx = ((det.left + det.width / 2) - 0.5).clamp(-0.5, 0.5);
    final yawRad = tracking.cameraEulerDegrees.y * pi / 180.0;
    final look = tracking.lookAtPosition;
    final depth = (tracking.depthHintMeters ?? 1.8).clamp(0.7, 5.5);
    late final double worldX;
    late final double worldZ;
    if (look != null && tracking.hasFloorHit) {
      final rightX = cos(yawRad);
      final rightZ = -sin(yawRad);
      final lateral = cx * depth * 0.35;
      worldX = (look.x + rightX * lateral).clamp(0.15, dimensions.lengthMeters - 0.15);
      worldZ = (look.z + rightZ * lateral).clamp(0.15, dimensions.widthMeters - 0.15);
    } else {
      final forwardX = sin(yawRad);
      final forwardZ = cos(yawRad);
      final rightX = cos(yawRad);
      final rightZ = -sin(yawRad);
      final lateral = cx * depth * 0.55;
      worldX = (tracking.cameraPosition.x + forwardX * depth + rightX * lateral)
          .clamp(0.15, dimensions.lengthMeters - 0.15);
      worldZ = (tracking.cameraPosition.z + forwardZ * depth + rightZ * lateral)
          .clamp(0.15, dimensions.widthMeters - 0.15);
    }

    final depthWeight = (1.6 / depth).clamp(0.55, 1.35);
    final estWidth = (det.width * dimensions.lengthMeters * 0.45 * depthWeight).clamp(0.35, 1.8);
    final estDepth = (det.height * dimensions.widthMeters * 0.35 * depthWeight).clamp(0.35, 1.8);
    final estHeight = ((det.height * dimensions.heightMeters) * 0.85 * depthWeight).clamp(0.4, 2.0);

    final id = '${det.label.toLowerCase().replaceAll(' ', '_')}_${worldX.toStringAsFixed(1)}_${worldZ.toStringAsFixed(1)}';
    final confBoost = tracking.confidence.clamp(0.0, 1.0);
    final confidence = (det.confidence * 0.75 + confBoost * 0.25).clamp(0.0, 1.0);

    return ScanObject(
      id: id,
      label: det.label,
      category: det.category,
      confidence: confidence,
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
