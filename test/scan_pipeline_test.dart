import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';

class _FakeTrackingProvider implements TrackingProvider {
  final bool stable;

  _FakeTrackingProvider({required this.stable});

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<TrackingSample> update(ScanFrameInput frame) async {
    return TrackingSample(
      cameraPosition: const Vec3(x: 1.0, y: 1.5, z: 1.0),
      cameraEulerDegrees: const Vec3(x: 0, y: 0, z: 0),
      trackingStable: stable,
    );
  }
}

class _FakeQualityAnalyzer implements FrameQualityAnalyzer {
  final ScanQualityReport report;

  const _FakeQualityAnalyzer(this.report);

  @override
  Future<ScanQualityReport> analyze(ScanFrameInput frame) async => report;
}

class _FakeObjectDetector implements ObjectDetector {
  final List<Detection2D> detections;

  const _FakeObjectDetector(this.detections);

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async => detections;
}

class _ThrowingTrackingProvider implements TrackingProvider {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<TrackingSample> update(ScanFrameInput frame) async {
    throw StateError('tracking unavailable');
  }
}

class _ThrowingObjectDetector implements ObjectDetector {
  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    throw StateError('detector unavailable');
  }
}

void main() {
  group('ScanPipeline', () {
    test('throws if processFrame called before initialize', () async {
      final pipeline = ScanPipeline(
        trackingProvider: _FakeTrackingProvider(stable: true),
        qualityAnalyzer: const _FakeQualityAnalyzer(
          ScanQualityReport(acceptable: true, issues: []),
        ),
        objectDetector: const _FakeObjectDetector([]),
        fusionEngine: GridCoverageFusionEngine(),
      );

      await expectLater(
        () => pipeline.processFrame(
          ScanFrameInput(
            timestamp: DateTime(2026, 1, 1),
            width: 4,
            height: 4,
            bytes: List<int>.filled(16, 120),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('marks quality unacceptable when tracking is unstable', () async {
      final pipeline = ScanPipeline(
        trackingProvider: _FakeTrackingProvider(stable: false),
        qualityAnalyzer: const _FakeQualityAnalyzer(
          ScanQualityReport(acceptable: true, issues: []),
        ),
        objectDetector: const _FakeObjectDetector([]),
        fusionEngine: GridCoverageFusionEngine(),
      );

      await pipeline.initialize(RoomLayoutModel.emptyFromRoom(RoomPresets.all.first));

      final tick = await pipeline.processFrame(
        ScanFrameInput(
          timestamp: DateTime(2026, 1, 1, 12),
          width: 8,
          height: 8,
          bytes: List<int>.filled(64, 130),
        ),
      );

      expect(tick.frameResult.quality.acceptable, isFalse);
      expect(tick.frameResult.quality.issues, contains(ScanQualityIssue.trackingLost));
    });

    test('falls back when tracking provider throws', () async {
      final pipeline = ScanPipeline(
        trackingProvider: _ThrowingTrackingProvider(),
        qualityAnalyzer: const _FakeQualityAnalyzer(
          ScanQualityReport(acceptable: true, issues: []),
        ),
        objectDetector: const _FakeObjectDetector([]),
        fusionEngine: GridCoverageFusionEngine(),
      );

      await pipeline.initialize(RoomLayoutModel.emptyFromRoom(RoomPresets.all.first));

      final tick = await pipeline.processFrame(
        ScanFrameInput(
          timestamp: DateTime(2026, 1, 2, 8),
          width: 8,
          height: 8,
          bytes: List<int>.filled(64, 128),
        ),
      );

      expect(tick.diagnostics.trackingFallbackUsed, isTrue);
      expect(tick.frameResult.quality.acceptable, isFalse);
      expect(tick.frameResult.quality.issues, contains(ScanQualityIssue.trackingLost));
    });

    test('falls back to empty detections when detector throws', () async {
      final pipeline = ScanPipeline(
        trackingProvider: _FakeTrackingProvider(stable: true),
        qualityAnalyzer: const _FakeQualityAnalyzer(
          ScanQualityReport(acceptable: true, issues: []),
        ),
        objectDetector: _ThrowingObjectDetector(),
        fusionEngine: GridCoverageFusionEngine(),
      );

      await pipeline.initialize(RoomLayoutModel.emptyFromRoom(RoomPresets.all.first));

      final tick = await pipeline.processFrame(
        ScanFrameInput(
          timestamp: DateTime(2026, 1, 2, 9),
          width: 8,
          height: 8,
          bytes: List<int>.filled(64, 128),
        ),
      );

      expect(tick.diagnostics.detectorFallbackUsed, isTrue);
      expect(tick.frameResult.detections, isEmpty);
    });
  });

  group('GridCoverageFusionEngine', () {
    test('keeps locked object unchanged while fusing detections', () {
      final engine = GridCoverageFusionEngine();
      final seed = RoomLayoutModel(
        roomName: 'Test Room',
        dimensions: const RoomDimensions(lengthMeters: 6, widthMeters: 4, heightMeters: 2.8),
        objects: const [
          ScanObject(
            id: 'desk_1',
            label: 'Desk',
            category: 'ergonomics',
            confidence: 0.9,
            center: Vec3(x: 1.0, y: 0.5, z: 1.0),
            sizeMeters: Vec3(x: 1.2, y: 1.0, z: 0.7),
            yawDegrees: 0,
            source: 'seed',
            locked: true,
          ),
        ],
        coverageGrid: CoverageGrid(cols: 8, rows: 6, coverage: List<double>.filled(48, 0)),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final state = engine.initialize(seed);
      final next = engine.fuseFrame(
        current: state,
        frame: const ScanFrameResult(
          tracking: TrackingSample(
            cameraPosition: Vec3(x: 2, y: 1.5, z: 2),
            cameraEulerDegrees: Vec3(x: 0, y: 45, z: 0),
            trackingStable: true,
          ),
          quality: ScanQualityReport(acceptable: true, issues: []),
          detections: [
            Detection2D(
              label: 'Desk',
              category: 'ergonomics',
              confidence: 0.6,
              left: 0.7,
              top: 0.7,
              width: 0.2,
              height: 0.2,
            ),
          ],
        ),
      );

      final lockedDesk = next.layout.objects.firstWhere((o) => o.id == 'desk_1');
      expect(lockedDesk.center.x, 1.0);
      expect(lockedDesk.center.z, 1.0);
      expect(lockedDesk.locked, isTrue);
      expect(next.layout.coverageGrid.ratio(), greaterThan(0));
    });

    test('prunes stale unlocked scan-fusion objects when confidence decays below threshold', () {
      final engine = GridCoverageFusionEngine();
      final seed = RoomLayoutModel(
        roomName: 'Decay Room',
        dimensions: const RoomDimensions(lengthMeters: 6, widthMeters: 4, heightMeters: 2.8),
        objects: const [
          ScanObject(
            id: 'stale_obj',
            label: 'Shelf',
            category: 'neutral',
            confidence: 0.20,
            center: Vec3(x: 1.2, y: 0.6, z: 2.0),
            sizeMeters: Vec3(x: 0.8, y: 1.2, z: 0.4),
            yawDegrees: 0,
            source: 'scan-fusion',
            locked: false,
          ),
        ],
        coverageGrid: CoverageGrid(cols: 8, rows: 6, coverage: List<double>.filled(48, 0)),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final next = engine.fuseFrame(
        current: engine.initialize(seed),
        frame: const ScanFrameResult(
          tracking: TrackingSample(
            cameraPosition: Vec3(x: 2, y: 1.5, z: 2),
            cameraEulerDegrees: Vec3(x: 0, y: 0, z: 0),
            trackingStable: true,
          ),
          quality: ScanQualityReport(acceptable: true, issues: []),
          detections: [],
        ),
      );

      expect(next.layout.objects.where((o) => o.id == 'stale_obj'), isEmpty);
    });

    test('keeps locked scan-fusion objects even when stale', () {
      final engine = GridCoverageFusionEngine();
      final seed = RoomLayoutModel(
        roomName: 'Lock Room',
        dimensions: const RoomDimensions(lengthMeters: 6, widthMeters: 4, heightMeters: 2.8),
        objects: const [
          ScanObject(
            id: 'locked_obj',
            label: 'Cabinet',
            category: 'neutral',
            confidence: 0.20,
            center: Vec3(x: 1.2, y: 0.6, z: 2.0),
            sizeMeters: Vec3(x: 0.8, y: 1.2, z: 0.4),
            yawDegrees: 0,
            source: 'scan-fusion',
            locked: true,
          ),
        ],
        coverageGrid: CoverageGrid(cols: 8, rows: 6, coverage: List<double>.filled(48, 0)),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final next = engine.fuseFrame(
        current: engine.initialize(seed),
        frame: const ScanFrameResult(
          tracking: TrackingSample(
            cameraPosition: Vec3(x: 2, y: 1.5, z: 2),
            cameraEulerDegrees: Vec3(x: 0, y: 0, z: 0),
            trackingStable: true,
          ),
          quality: ScanQualityReport(acceptable: true, issues: []),
          detections: [],
        ),
      );

      final locked = next.layout.objects.singleWhere((o) => o.id == 'locked_obj');
      expect(locked.locked, isTrue);
      expect(locked.confidence, 0.20);
    });
  });
}
