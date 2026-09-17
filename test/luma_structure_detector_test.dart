import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';

void main() {
  test('LumaStructureObjectDetector finds blobs in textured frames', () async {
    const w = 64;
    const h = 48;
    final bytes = Uint8List(w * h);
    // Flat background.
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 90;
    }
    // Bright textured rectangle (desk-like) in lower mid.
    for (int y = 28; y < 42; y++) {
      for (int x = 12; x < 44; x++) {
        bytes[y * w + x] = (140 + ((x + y) % 40)).clamp(100, 220);
      }
    }

    final detector = LumaStructureObjectDetector();
    List<Detection2D> last = const [];
    for (int i = 0; i < 6; i++) {
      last = await detector.detect(
        ScanFrameInput(
          timestamp: DateTime.utc(2026, 7, 22, 0, 0, i),
          width: w,
          height: h,
          bytes: bytes,
        ),
      );
    }

    expect(last, isNotEmpty);
    expect(last.first.confidence, greaterThan(0.5));
    expect(last.first.width, greaterThan(0.05));
    expect(last.first.height, greaterThan(0.05));
  });
}
