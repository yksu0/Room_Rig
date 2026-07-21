import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';

void main() {
  group('YoloLikePostProcessor', () {
    test('decodes [1, features, count] output and applies label/category mapping', () {
      // Shape: [1, 7, 2] => features: [cx, cy, w, h, obj, class0, class1]
      final output = [
        [
          [0.50, 0.25], // cx
          [0.50, 0.25], // cy
          [0.20, 0.10], // w
          [0.20, 0.10], // h
          [0.90, 0.80], // obj
          [0.10, 0.90], // class0 (chair)
          [0.90, 0.10], // class1 (window)
        ]
      ];

      final detections = YoloLikePostProcessor.decode(
        rawOutput: output,
        outputShape: const [1, 7, 2],
        labels: const ['chair', 'window'],
        inputWidth: 640,
        inputHeight: 640,
        scoreThreshold: 0.2,
        iouThreshold: 0.45,
        maxDetections: 5,
      );

      expect(detections.length, 2);
      expect(detections.any((d) => d.label == 'Chair' && d.category == 'ergonomics'), isTrue);
      expect(detections.any((d) => d.label == 'Window' && d.category == 'lighting'), isTrue);
    });

    test('suppresses overlapping boxes with NMS for same class', () {
      final output = [
        [
          [0.50, 0.52], // cx
          [0.50, 0.52], // cy
          [0.20, 0.20], // w
          [0.20, 0.20], // h
          [0.95, 0.90], // obj
          [0.95, 0.90], // class0
        ]
      ];

      final detections = YoloLikePostProcessor.decode(
        rawOutput: output,
        outputShape: const [1, 6, 2],
        labels: const ['chair'],
        inputWidth: 640,
        inputHeight: 640,
        scoreThreshold: 0.2,
        iouThreshold: 0.2,
        maxDetections: 5,
      );

      expect(detections.length, 1);
      expect(detections.first.label, 'Chair');
    });
  });
}
