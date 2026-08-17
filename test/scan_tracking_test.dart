import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';

ScanFrameInput _texturedFrame({required int seed, int w = 64, int h = 48}) {
  final bytes = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bytes[y * w + x] = (80 + ((x + seed) % 40) + ((y + seed * 3) % 30)).clamp(40, 220);
    }
  }
  return ScanFrameInput(
    timestamp: DateTime.utc(2026, 7, 22, 0, 0, seed % 60),
    width: w,
    height: h,
    bytes: bytes,
  );
}

void main() {
  test('VisualOdometryEstimator moves pose from textured frame deltas', () {
    final vo = VisualOdometryEstimator();
    vo.reset(seedPosition: const Vec3(x: 1.5, y: 1.5, z: 1.5));
    const bounds = RoomDimensions(lengthMeters: 4, widthMeters: 5, heightMeters: 2.7);

    TrackingSample? last;
    for (int i = 0; i < 8; i++) {
      last = vo.update(_texturedFrame(seed: i * 3), roomBounds: bounds);
    }

    expect(last, isNotNull);
    expect(last!.source, 'visual');
    expect(last.confidence, greaterThan(0));
    expect(last.depthHintMeters, isNotNull);
    expect(last.cameraPosition.x, inInclusiveRange(0.25, 3.75));
    expect(last.cameraPosition.z, inInclusiveRange(0.25, 4.75));
  });

  test('CompositeTrackingProvider falls back to visual/simulated off-mobile', () async {
    final provider = CompositeTrackingProvider(
      roomBounds: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
    );
    await provider.initialize();

    final samples = <TrackingSample>[];
    for (int i = 0; i < 6; i++) {
      samples.add(await provider.update(_texturedFrame(seed: i + 1)));
    }
    await provider.dispose();

    expect(samples, isNotEmpty);
    expect(samples.every((s) => s.confidence > 0), isTrue);
    expect(
      samples.any((s) => s.source == 'visual' || s.source == 'simulated' || s.source == 'fused'),
      isTrue,
    );
  });

  test('CompositeTrackingProvider uses attachedTracking without re-polling', () async {
    final provider = CompositeTrackingProvider(
      roomBounds: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
    );
    await provider.initialize();

    const attached = TrackingSample(
      cameraPosition: Vec3(x: 1.1, y: 1.5, z: 2.2),
      cameraEulerDegrees: Vec3(x: 0, y: 45, z: 0),
      trackingStable: true,
      confidence: 0.91,
      source: 'arcore-s10',
      motionMeters: 0.02,
      depthHintMeters: 2.0,
    );
    final frame = ScanFrameInput(
      timestamp: DateTime.utc(2026, 7, 22),
      width: 32,
      height: 24,
      bytes: Uint8List(32 * 24),
      attachedTracking: attached,
    );

    final sample = await provider.update(frame);
    await provider.dispose();

    expect(sample.source, 'arcore-s10');
    expect(sample.cameraPosition.x, 1.1);
    expect(sample.confidence, 0.91);
  });

  test('CompositeTrackingProvider ignores weak attachedTracking', () async {
    final provider = CompositeTrackingProvider(
      roomBounds: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
    );
    await provider.initialize();

    const attached = TrackingSample(
      cameraPosition: Vec3(x: 0, y: 1.5, z: 0),
      cameraEulerDegrees: Vec3(x: 0, y: 0, z: 0),
      trackingStable: false,
      confidence: 0.2,
      source: 'arcore-s10',
    );
    final sample = await provider.update(
      ScanFrameInput(
        timestamp: DateTime.utc(2026, 7, 22),
        width: 32,
        height: 24,
        bytes: Uint8List(32 * 24),
        attachedTracking: attached,
      ),
    );
    await provider.dispose();

    expect(sample.source, isNot('arcore-s10'));
  });

  test('ScanPipeline diagnostics expose tracking source and confidence', () async {
    final pipeline = ScanPipeline(
      trackingProvider: CompositeTrackingProvider(
        roomBounds: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
      ),
      qualityAnalyzer: BasicFrameQualityAnalyzer(),
      objectDetector: HeuristicObjectDetector(),
      fusionEngine: GridCoverageFusionEngine(),
    );

    await pipeline.initialize(
      RoomLayoutModel.emptyFromRoom(RoomPresets.getPreset(RoomPreset.gamingSetup)),
    );

    final tick = await pipeline.processFrame(_texturedFrame(seed: 9));
    expect(tick.diagnostics.trackingSource, isNotEmpty);
    expect(tick.diagnostics.trackingConfidence, greaterThan(0));
    await pipeline.dispose();
  });
}
