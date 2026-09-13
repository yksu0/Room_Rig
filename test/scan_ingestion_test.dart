import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/scan_input_provider.dart';
import 'package:room_rig/services/scan_layout_converter.dart';
import 'package:room_rig/services/scan_pipeline.dart';
import 'package:room_rig/services/scan_pipeline_stubs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScanLayoutConverter', () {
    test('finalizeLayout ensures door and window openings', () {
      final seed = RoomLayoutModel.emptyFromRoom(RoomPresets.getPreset(RoomPreset.gamingSetup));
      final withDesk = seed.withObjects(const [
        ScanObject(
          id: 'desk_1',
          label: 'Desk',
          category: 'ergonomics',
          confidence: 0.9,
          center: Vec3(x: 1.5, y: 0.5, z: 1.2),
          sizeMeters: Vec3(x: 1.2, y: 0.8, z: 0.7),
          yawDegrees: 0,
          source: 'scan-fusion',
        ),
      ]);

      final finalized = ScanLayoutConverter.finalizeLayout(
        withDesk,
        gridCols: 6,
        gridRows: 8,
        inputProviderId: 'simulated',
      );

      expect(finalized.objects.any((o) => o.label.toLowerCase().contains('door')), isTrue);
      expect(finalized.objects.any((o) => o.label.toLowerCase().contains('window')), isTrue);
      expect(finalized.confidence, isNotNull);
      expect(finalized.confidence!.overallScore, greaterThan(0));
      expect(finalized.scanSource, 'simulated');
    });

    test('refineDimensionsFromObjects nudges oversized room claims', () {
      final refined = ScanLayoutConverter.refineDimensionsFromObjects(
        const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
        const [
          ScanObject(
            id: 'bed_1',
            label: 'bed',
            category: 'neutral',
            confidence: 0.9,
            center: Vec3(x: 1.5, y: 0.4, z: 2.0),
            // Claims almost the whole room length — should scale length up toward bed prior.
            sizeMeters: Vec3(x: 2.5, y: 0.5, z: 1.0),
            yawDegrees: 0,
            source: 'scan-fusion',
          ),
        ],
      );
      expect(refined.usedObjectScale, isTrue);
      expect(refined.dimensions.lengthMeters, greaterThan(3.6));
    });

    test('COCO couch/tv labels map to Rig sofa/tv icons', () {
      final layout = ScanLayoutConverter.finalizeLayout(
        RoomLayoutModel(
          roomName: 'Map',
          dimensions: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
          coverageGrid: CoverageGrid.empty(cols: 6, rows: 8),
          objects: const [
            ScanObject(
              id: 'c1',
              label: 'couch',
              category: 'neutral',
              confidence: 0.9,
              center: Vec3(x: 1, y: 0.4, z: 2),
              sizeMeters: Vec3(x: 1.8, y: 0.8, z: 0.9),
              yawDegrees: 0,
              source: 'yolo',
            ),
            ScanObject(
              id: 't1',
              label: 'tv',
              category: 'neutral',
              confidence: 0.9,
              center: Vec3(x: 2.5, y: 0.6, z: 2),
              sizeMeters: Vec3(x: 1.0, y: 0.7, z: 0.15),
              yawDegrees: 0,
              source: 'yolo',
            ),
          ],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        gridCols: 6,
        gridRows: 8,
      );
      final items = ScanLayoutConverter.toFurniture(layout, gridCols: 6, gridRows: 8);
      expect(items.any((f) => f.iconName == 'sofa'), isTrue);
      expect(items.any((f) => f.iconName == 'tv'), isTrue);
    });

    test('toFurniture maps detections onto the grid', () {
      final layout = ScanLayoutConverter.finalizeLayout(
        RoomLayoutModel(
          roomName: 'Test',
          dimensions: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
          coverageGrid: CoverageGrid.empty(cols: 6, rows: 8),
          objects: const [
            ScanObject(
              id: 'chair_a',
              label: 'Chair',
              category: 'ergonomics',
              confidence: 0.8,
              center: Vec3(x: 1.0, y: 0.5, z: 2.0),
              sizeMeters: Vec3(x: 0.7, y: 1.0, z: 0.7),
              yawDegrees: 0,
              source: 'scan-fusion',
            ),
          ],
          updatedAt: DateTime.utc(2026, 7, 22),
        ),
        gridCols: 6,
        gridRows: 8,
        inputProviderId: 'test',
      );

      final furniture = ScanLayoutConverter.toFurniture(layout, gridCols: 6, gridRows: 8);
      expect(furniture.any((f) => f.iconName == 'chair'), isTrue);
      expect(furniture.any((f) => f.iconName == 'door'), isTrue);
      expect(furniture.any((f) => f.iconName == 'window'), isTrue);
    });
    test('toFurniture maps COCO couch/tv/laptop labels to room icons', () {
      final layout = ScanLayoutConverter.finalizeLayout(
        RoomLayoutModel(
          roomName: 'Test',
          dimensions: const RoomDimensions(lengthMeters: 3.6, widthMeters: 4.8, heightMeters: 2.7),
          coverageGrid: CoverageGrid.empty(cols: 6, rows: 8),
          objects: const [
            ScanObject(
              id: 'couch_1',
              label: 'Couch',
              category: 'ergonomics',
              confidence: 0.9,
              center: Vec3(x: 2.0, y: 0.5, z: 2.5),
              sizeMeters: Vec3(x: 1.8, y: 0.8, z: 0.9),
              yawDegrees: 0,
              source: 'scan-fusion',
            ),
            ScanObject(
              id: 'tv_1',
              label: 'Tv',
              category: 'lighting',
              confidence: 0.85,
              center: Vec3(x: 1.2, y: 0.8, z: 1.0),
              sizeMeters: Vec3(x: 1.0, y: 0.6, z: 0.2),
              yawDegrees: 0,
              source: 'scan-fusion',
            ),
            ScanObject(
              id: 'laptop_1',
              label: 'Laptop',
              category: 'lighting',
              confidence: 0.8,
              center: Vec3(x: 2.5, y: 0.5, z: 1.5),
              sizeMeters: Vec3(x: 0.4, y: 0.2, z: 0.3),
              yawDegrees: 0,
              source: 'scan-fusion',
            ),
          ],
          updatedAt: DateTime.utc(2026, 7, 22),
        ),
        gridCols: 6,
        gridRows: 8,
        inputProviderId: 'test',
      );

      final furniture = ScanLayoutConverter.toFurniture(layout, gridCols: 6, gridRows: 8);
      expect(furniture.any((f) => f.iconName == 'sofa'), isTrue);
      expect(furniture.any((f) => f.iconName == 'tv'), isTrue);
      expect(furniture.any((f) => f.iconName == 'pc'), isTrue);
    });
  });

  group('SimulatedScanInputProvider', () {
    test('emits textured frames', () async {
      final provider = SimulatedScanInputProvider(
        interval: const Duration(milliseconds: 30),
        width: 32,
        height: 24,
      );
      await provider.initialize();
      final frames = <ScanFrameInput>[];
      await provider.start(frames.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await provider.dispose();
      expect(frames, isNotEmpty);
      expect(frames.first.bytes.length, 32 * 24);
      expect(frames.first.bytes.any((b) => b > 40), isTrue);
    });
  });

  group('Scan commit path', () {
    test('commitScannedRoomLayout replaces furniture and marks scan complete', () async {
      final state = AppState();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final seed = RoomLayoutModel.emptyFromRoom(state.currentRoomData).withObjects(const [
        ScanObject(
          id: 'desk_scan',
          label: 'Desk',
          category: 'ergonomics',
          confidence: 0.88,
          center: Vec3(x: 1.2, y: 0.5, z: 1.0),
          sizeMeters: Vec3(x: 1.4, y: 0.8, z: 0.7),
          yawDegrees: 0,
          source: 'scan-fusion',
        ),
        ScanObject(
          id: 'chair_scan',
          label: 'Chair',
          category: 'ergonomics',
          confidence: 0.81,
          center: Vec3(x: 1.2, y: 0.5, z: 1.8),
          sizeMeters: Vec3(x: 0.7, y: 1.0, z: 0.7),
          yawDegrees: 0,
          source: 'scan-fusion',
        ),
      ]);

      // Mark some coverage so confidence is meaningful.
      var covered = seed;
      for (int c = 0; c < 6; c++) {
        for (int r = 0; r < 8; r++) {
          covered = covered.withCoverage(covered.coverageGrid.markCell(c, r, 0.85));
        }
      }

      state.commitScannedRoomLayout(
        covered,
        inputProviderId: 'simulated',
        usedFallback: true,
      );

      expect(state.scanComplete, isTrue);
      expect(state.furniture.any((f) => f.iconName == 'desk'), isTrue);
      expect(state.furniture.any((f) => f.iconName == 'door'), isTrue);
      expect(state.lastScanConfidence, isNotNull);
      expect(state.lastScanConfidence!.inputProviderId, 'simulated');
    });

    test('pipeline + simulated provider can produce a finalizable layout', () async {
      final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
      final pipeline = ScanPipeline(
        trackingProvider: ArCoreTrackingProviderStub(),
        qualityAnalyzer: BasicFrameQualityAnalyzer(),
        objectDetector: HeuristicObjectDetector(),
        fusionEngine: GridCoverageFusionEngine(),
      );
      final input = SimulatedScanInputProvider(interval: const Duration(milliseconds: 20));
      await pipeline.initialize(RoomLayoutModel.emptyFromRoom(room));
      await input.initialize();

      RoomLayoutModel? latest;
      await input.start((frame) async {
        final tick = await pipeline.processFrame(frame);
        latest = tick.layout;
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await input.dispose();

      final finalized = pipeline.finalize();
      expect(latest, isNotNull);
      expect(finalized.confidence, isNotNull);
      expect(
        finalized.objects.any((o) => o.label.toLowerCase().contains('door')),
        isTrue,
      );
      await pipeline.dispose();
    });
  });

  test('CoverageGrid.markCell keeps the stronger value', () {
    var grid = CoverageGrid.empty(cols: 3, rows: 3).markCell(1, 1, 1.0);
    grid = grid.markCell(1, 1, 0.45);
    expect(grid.coverage[4], 1.0);
    grid = grid.markCell(1, 1, 0.9);
    expect(grid.coverage[4], 1.0);
  });
}
