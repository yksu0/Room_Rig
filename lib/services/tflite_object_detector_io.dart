import 'dart:math';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'scan_pipeline.dart';
import 'scan_pipeline_stubs.dart';

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
    if (interpreter == null || frame.bytes.isEmpty) {
      return const [];
    }

    try {
      final input = _buildInputTensor(frame.bytes, frame.width, frame.height);
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

  dynamic _buildInputTensor(List<int> lumaBytes, int srcWidth, int srcHeight) {
    final srcW = srcWidth > 0 ? srcWidth : max(1, sqrt(lumaBytes.length).round());
    final srcH = srcHeight > 0 ? srcHeight : max(1, lumaBytes.length ~/ srcW);

    if (_inputIsNhwc) {
      return List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (y) => List.generate(_inputWidth, (x) {
            final pixel = _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight, srcW, srcH) / 255.0;
            return <double>[pixel, pixel, pixel];
          }),
        ),
      );
    }

    return List.generate(
      1,
      (_) => List.generate(
        3,
        (_) => List.generate(_inputHeight, (y) {
          return List.generate(_inputWidth, (x) {
            return _sampleLuma(lumaBytes, x, y, _inputWidth, _inputHeight, srcW, srcH) / 255.0;
          });
        }),
      ),
    );
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

  dynamic _createZeros(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List<double>.filled(shape.first, 0.0);
    return List.generate(shape.first, (_) => _createZeros(shape.sublist(1)));
  }
}
