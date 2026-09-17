import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'scan_pipeline.dart';
import 'scan_pipeline_stubs.dart';

/// On-device YOLO detector using flat Float32 buffers (no nested List tensors).
///
/// Nested `[1][640][640][3]` / `[1][84][8400]` Dart lists OOMed mid/low-end phones.
class TfliteObjectDetector implements ObjectDetector {
  static const labelsAssetPath = 'assets/models/yolo_roomrig_labels.txt';

  /// Min gap between full YOLO runs. Between runs we reuse the last boxes.
  static const Duration inferenceInterval = Duration(milliseconds: 900);

  final String modelAssetPath;
  final double scoreThreshold;
  final double iouThreshold;
  final int maxDetections;
  final List<String> classLabels;

  bool _initAttempted = false;
  bool _disabled = false;
  Interpreter? _interpreter;
  int _inputWidth = 640;
  int _inputHeight = 640;
  bool _inputIsNhwc = true;
  late List<String> _resolvedLabels;

  Float32List? _inputFloats;
  Uint8List? _inputBytes;
  Float32List? _outputFloats;
  Uint8List? _outputBytes;
  List<int> _outputShape = const [];

  DateTime? _lastInferAt;
  List<Detection2D> _lastResults = const [];
  int _consecutiveFailures = 0;

  TfliteObjectDetector({
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
  }) {
    _resolvedLabels = List<String>.from(classLabels);
  }

  bool get isDisabled => _disabled;

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    if (_disabled) return const [];

    await _ensureInterpreter();
    final interpreter = _interpreter;
    if (interpreter == null || frame.bytes.isEmpty) {
      return const [];
    }

    final now = DateTime.now();
    final last = _lastInferAt;
    if (last != null && now.difference(last) < inferenceInterval) {
      return _lastResults;
    }

    try {
      _fillInput(frame.bytes, frame.width, frame.height);

      final inTensor = interpreter.getInputTensor(0);
      inTensor.data = _inputBytes!;

      interpreter.invoke();

      final outTensor = interpreter.getOutputTensor(0);
      final native = outTensor.data;
      final outBytes = _outputBytes!;
      if (native.length != outBytes.length) {
        throw StateError(
          'YOLO output size mismatch: native=${native.length} buf=${outBytes.length}',
        );
      }
      outBytes.setRange(0, native.length, native);

      final decoded = YoloLikePostProcessor.decode(
        rawOutput: _outputFloats!,
        outputShape: _outputShape,
        labels: _resolvedLabels,
        inputWidth: _inputWidth,
        inputHeight: _inputHeight,
        scoreThreshold: scoreThreshold,
        iouThreshold: iouThreshold,
        maxDetections: maxDetections,
      );
      final kept = decoded.where(_isRoomRelevantLabel).toList(growable: false);

      _lastInferAt = now;
      _lastResults = kept;
      _consecutiveFailures = 0;
      return kept;
    } catch (e, st) {
      _consecutiveFailures++;
      debugPrint('TfliteObjectDetector.detect failed: $e\n$st');
      if (_consecutiveFailures >= 2) {
        _disable('repeated detect failures');
      }
      return const [];
    }
  }

  Future<void> _ensureInterpreter() async {
    if (_initAttempted || _disabled) return;
    _initAttempted = true;

    try {
      final fromAsset = await _loadLabelsFromAsset();
      if (fromAsset != null && fromAsset.isNotEmpty) {
        _resolvedLabels = fromAsset;
        debugPrint(
          'TfliteObjectDetector: loaded ${fromAsset.length} labels from $labelsAssetPath',
        );
      }

      final options = InterpreterOptions()..threads = 1;
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

      final inElems = inputTensor.numElements();
      _inputFloats = Float32List(inElems);
      _inputBytes = Uint8List.view(
        _inputFloats!.buffer,
        _inputFloats!.offsetInBytes,
        inElems * 4,
      );

      final outputTensor = interpreter.getOutputTensor(0);
      _outputShape = List<int>.from(outputTensor.shape);
      final outElems = outputTensor.numElements();
      _outputFloats = Float32List(outElems);
      _outputBytes = Uint8List.view(
        _outputFloats!.buffer,
        _outputFloats!.offsetInBytes,
        outElems * 4,
      );

      _interpreter = interpreter;
      debugPrint(
        'TfliteObjectDetector: ready ($modelAssetPath, '
        '${_inputWidth}x$_inputHeight, nhwc=$_inputIsNhwc, '
        'in=$inElems out=$outElems)',
      );
    } catch (e, st) {
      debugPrint('TfliteObjectDetector init failed ($modelAssetPath): $e\n$st');
      _disable('init failed');
    }
  }

  void _disable(String reason) {
    if (_disabled) return;
    _disabled = true;
    debugPrint('TfliteObjectDetector: disabled ($reason) — using heuristic fallback');
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _inputFloats = null;
    _inputBytes = null;
    _outputFloats = null;
    _outputBytes = null;
    _lastResults = const [];
  }

  Future<List<String>?> _loadLabelsFromAsset() async {
    try {
      final raw = await rootBundle.loadString(labelsAssetPath);
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      return lines.isEmpty ? null : lines;
    } catch (_) {
      return null;
    }
  }

  void _fillInput(List<int> lumaBytes, int srcWidth, int srcHeight) {
    final buf = _inputFloats!;
    final srcW = srcWidth > 0 ? srcWidth : max(1, sqrt(lumaBytes.length).round());
    final srcH = srcHeight > 0 ? srcHeight : max(1, lumaBytes.length ~/ srcW);
    var i = 0;

    if (_inputIsNhwc) {
      for (int y = 0; y < _inputHeight; y++) {
        for (int x = 0; x < _inputWidth; x++) {
          final pixel =
              _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight, srcW, srcH) / 255.0;
          buf[i++] = pixel;
          buf[i++] = pixel;
          buf[i++] = pixel;
        }
      }
      return;
    }

    final plane = _inputHeight * _inputWidth;
    for (int y = 0; y < _inputHeight; y++) {
      for (int x = 0; x < _inputWidth; x++) {
        final pixel =
            _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight, srcW, srcH) / 255.0;
        final idx = y * _inputWidth + x;
        buf[idx] = pixel;
        buf[plane + idx] = pixel;
        buf[plane * 2 + idx] = pixel;
      }
    }
  }

  static bool _isRoomRelevantLabel(Detection2D det) {
    final v = det.label.toLowerCase();
    const keep = <String>[
      'chair',
      'couch',
      'sofa',
      'bed',
      'table',
      'tv',
      'laptop',
      'monitor',
      'plant',
      'book',
      'clock',
      'vase',
      'refrigerator',
      'microwave',
      'oven',
      'sink',
      'toilet',
      'keyboard',
      'mouse',
      'desk',
      'lamp',
      'fan',
      'window',
      'door',
      'shelf',
      'cabinet',
      'ac',
    ];
    return keep.any(v.contains);
  }

  int _sampleLuma(
    List<int> bytes,
    int x,
    int y,
    int dstW,
    int dstH,
    int srcW,
    int srcH,
  ) {
    if (bytes.isEmpty || srcW <= 0 || srcH <= 0) return 0;
    final sx = ((x + 0.5) * srcW / dstW).floor().clamp(0, srcW - 1);
    final sy = ((y + 0.5) * srcH / dstH).floor().clamp(0, srcH - 1);
    final idx = sy * srcW + sx;
    if (idx < 0 || idx >= bytes.length) return 0;
    return bytes[idx];
  }
}

/// Compat alias for older call sites.
typedef TfliteObjectDetectorPlaceholder = TfliteObjectDetector;
