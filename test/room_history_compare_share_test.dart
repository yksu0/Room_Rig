import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/saved_room.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/services/layout_share_image.dart';
import 'package:room_rig/services/room_compare.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  FurnitureItem fan({required String id, double x = 1, double y = 1}) => FurnitureItem(
        id: id,
        name: 'Fan',
        iconName: 'fan',
        category: 'airflow',
        gridX: x,
        gridY: y,
      );

  test('checkpointActiveRoom appends a revision', () {
    final state = AppState();
    expect(state.activeRoomRevisions, isEmpty);
    state.checkpointActiveRoom('Manual save');
    expect(state.activeRoomRevisions, isNotEmpty);
    expect(state.activeRoomRevisions.last.label, 'Manual save');
  });

  test('restoreRoomRevision reloads furniture', () {
    final state = AppState();
    final first = List<FurnitureItem>.from(state.furniture);
    state.checkpointActiveRoom('Before move');
    if (state.furniture.isNotEmpty) {
      final id = state.furniture.first.id;
      state.moveFurniture(id, 6, 6, respectCollision: false);
    }
    final revId = state.activeRoomRevisions.last.id;
    expect(state.restoreRoomRevision(revId), isTrue);
    expect(state.furniture.length, first.length);
  });

  test('RoomCompare reports layout diff between rooms', () {
    final layout = RoomLayoutModel(
      roomName: 'A',
      dimensions: const RoomDimensions(lengthMeters: 4, widthMeters: 4, heightMeters: 2.5),
      objects: const [],
      coverageGrid: CoverageGrid.empty(cols: 8, rows: 8),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final a = SavedRoom(
      id: 'a',
      name: 'A',
      presetName: 'gamingSetup',
      scanComplete: false,
      scanProgress: 0,
      layout: layout,
      furniture: [fan(id: 'fan', x: 1, y: 1)],
    );
    final b = SavedRoom(
      id: 'b',
      name: 'B',
      presetName: 'gamingSetup',
      scanComplete: false,
      scanProgress: 0,
      layout: layout,
      furniture: [fan(id: 'fan', x: 3, y: 2)],
    );
    final cmp = RoomCompare.compare(a, b);
    expect(cmp.layoutDiff, contains('moved'));
    expect(cmp.scoresA['overall'], isNotNull);
    expect(cmp.scoresB['overall'], isNotNull);
  });

  test('LayoutShareImage renders a PNG byte buffer', () async {
    final png = await LayoutShareImage.renderBeforeAfterPng(
      gridCols: 8,
      gridRows: 8,
      before: [fan(id: 'fan', x: 1, y: 1)],
      after: [fan(id: 'fan', x: 3, y: 2)],
      footer: 'moved Fan',
    );
    expect(png.length, greaterThan(100));
    // PNG magic header
    expect(png[0], 0x89);
    expect(png[1], 0x50);
  });
}
