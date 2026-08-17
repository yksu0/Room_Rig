import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/rig_catalog.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/screens/rig_customizer_screen.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/widgets/room_orbit_projection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  Future<AppState> pumpRig(WidgetTester tester) async {
    final state = AppState();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: RigCustomizerScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return state;
  }

  group('floor-plane unprojection', () {
    const cam = CameraPose(
      roomWidth: 6,
      roomDepth: 8,
      roomHeight: 2.8,
      yaw: 0.4,
      pitch: 0.34,
      distance: 15,
    );
    const size = Size(800, 600);

    test('round-trips a floor point through project and back', () {
      for (final point in const [
        OrbitVec3(1, 0, 1),
        OrbitVec3(3, 0, 4),
        OrbitVec3(5.5, 0, 7.5),
      ]) {
        final screen = RoomProjection.project(point, size, cam);
        expect(screen, isNotNull, reason: 'point should be on screen');

        final floor = RoomProjection.unprojectToFloor(screen!.offset, size, cam);
        expect(floor, isNotNull);
        expect(floor!.dx, closeTo(point.x, 0.001));
        expect(floor.dy, closeTo(point.z, 0.001));
      }
    });

    test('round-trips across yaw and pitch changes', () {
      const target = OrbitVec3(2, 0, 5);
      for (final yaw in [-2.0, -0.7, 0.0, 1.1, 3.0]) {
        for (final pitch in [0.05, 0.34, 0.9]) {
          final pose = CameraPose(
            roomWidth: 6,
            roomDepth: 8,
            roomHeight: 2.8,
            yaw: yaw,
            pitch: pitch,
            distance: 15,
          );
          final screen = RoomProjection.project(target, size, pose);
          if (screen == null) continue;
          final floor = RoomProjection.unprojectToFloor(screen.offset, size, pose);
          expect(floor, isNotNull, reason: 'yaw $yaw pitch $pitch');
          expect(floor!.dx, closeTo(target.x, 0.01), reason: 'yaw $yaw pitch $pitch');
          expect(floor.dy, closeTo(target.z, 0.01), reason: 'yaw $yaw pitch $pitch');
        }
      }
    });

    test('dragging down the screen walks the floor toward the camera', () {
      const facing = CameraPose(
        roomWidth: 6,
        roomDepth: 8,
        roomHeight: 2.8,
        yaw: 0,
        pitch: 0.34,
        distance: 15,
      );
      final higher = RoomProjection.unprojectToFloor(const Offset(400, 340), size, facing)!;
      final lower = RoomProjection.unprojectToFloor(const Offset(400, 400), size, facing)!;

      // At yaw 0 the camera sits on the +z side, so lower on screen is nearer.
      expect(lower.dy, greaterThan(higher.dy));
      // A straight vertical drag must not slide the item sideways.
      expect(lower.dx, closeTo(higher.dx, 0.001));
    });

    test('dragging sideways walks the floor along the camera right axis', () {
      const facing = CameraPose(
        roomWidth: 6,
        roomDepth: 8,
        roomHeight: 2.8,
        yaw: 0,
        pitch: 0.34,
        distance: 15,
      );
      final left = RoomProjection.unprojectToFloor(const Offset(340, 400), size, facing)!;
      final right = RoomProjection.unprojectToFloor(const Offset(460, 400), size, facing)!;

      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, closeTo(left.dy, 0.001));
    });

    test('returns null above the horizon', () {
      // A camera looking down from above has its horizon on screen; anything
      // dragged past it casts a ray that never meets the floor.
      final aboveHorizon = RoomProjection.unprojectToFloor(
        const Offset(400, -4000),
        size,
        cam,
      );
      expect(aboveHorizon, isNull);
    });
  });

  group('catalog placement', () {
    test('adds an item, selects it, and keeps ids unique', () {
      final state = AppState();
      const desk = RigCatalogEntry(
        baseId: 'desk',
        name: 'Desk',
        iconName: 'desk',
        category: 'ergonomics',
        width: 2,
      );

      // The gaming preset already ships a 'desk'.
      expect(state.furniture.any((f) => f.id == 'desk'), isTrue);

      final id = state.addCatalogFurniture(desk);
      expect(id, isNotNull);
      expect(id, isNot('desk'));
      expect(state.furniture.where((f) => f.id == id), hasLength(1));
      expect(state.selectedItemId, id);
      expect(state.selectedIsScanObject, isFalse);
      expect(state.canUndoLayout, isTrue);
    });

    test('placed item lands inside the room and clear of other furniture', () {
      final state = AppState();
      final room = state.currentRoomData;
      const bed = RigCatalogEntry(
        baseId: 'spare_bed',
        name: 'Bed',
        iconName: 'bed',
        category: 'neutral',
        width: 2,
        height: 2,
      );

      final id = state.addCatalogFurniture(bed);
      expect(id, isNotNull);

      final placed = state.furniture.firstWhere((f) => f.id == id);
      expect(placed.gridX, greaterThanOrEqualTo(0));
      expect(placed.gridY, greaterThanOrEqualTo(0));
      expect(placed.gridX + placed.width, lessThanOrEqualTo(room.gridCols.toDouble()));
      expect(placed.gridY + placed.height, lessThanOrEqualTo(room.gridRows.toDouble()));

      expect(
        state.layoutConflicts.any((c) => c.itemIds.contains(id)),
        isFalse,
        reason: 'a freshly placed item should not start in conflict',
      );
    });

    test('reports failure instead of stacking when the room is full', () {
      final state = AppState();
      const filler = RigCatalogEntry(
        baseId: 'filler',
        name: 'Filler',
        iconName: 'plant',
        category: 'neutral',
      );

      String? last;
      var placed = 0;
      // 6x8 grid, so this is guaranteed to run out of space.
      for (var i = 0; i < 60; i++) {
        last = state.addCatalogFurniture(filler);
        if (last == null) break;
        placed++;
      }

      expect(last, isNull, reason: 'the room must eventually refuse new items');
      expect(placed, lessThan(60));
      expect(state.addCatalogFurniture(filler), isNull);
    });

    test('every catalog entry fits an empty-ish room', () {
      for (final entry in RigCatalog.items) {
        final state = AppState();
        expect(
          state.addCatalogFurniture(entry),
          isNotNull,
          reason: '${entry.name} should be placeable',
        );
      }
    });
  });

  group('drag gesture batching', () {
    double fanCenterX(AppState state) =>
        state.activeRoomLayout!.objects.firstWhere((o) => o.id == 'fan').center.x;

    test('defers the layout rebuild until the gesture ends', () {
      final state = AppState();
      final before = state.activeRoomLayout;
      expect(before, isNotNull);
      final centerBefore = fanCenterX(state);

      state.beginFurnitureGesture();
      state.moveFurniture('fan', 2.0, 2.0);
      expect(
        identical(state.activeRoomLayout, before),
        isTrue,
        reason: 'mid-drag frames should not rebuild the layout model',
      );
      expect(fanCenterX(state), centerBefore);
      // The editable furniture list is still live so the canvas can follow.
      expect(state.furniture.firstWhere((f) => f.id == 'fan').gridX, isNot(4));

      state.endFurnitureGesture();
      expect(identical(state.activeRoomLayout, before), isFalse);
      expect(fanCenterX(state), isNot(centerBefore));
    });

    test('a whole drag collapses into one undo step', () {
      final state = AppState();
      state.clearLayoutHistory();
      final start = state.furniture.firstWhere((f) => f.id == 'fan');
      final startX = start.gridX;
      final startY = start.gridY;

      state.beginFurnitureGesture();
      for (var i = 1; i <= 8; i++) {
        state.moveFurniture('fan', startX - i * 0.1, startY);
      }
      state.endFurnitureGesture();

      final dragged = state.furniture.firstWhere((f) => f.id == 'fan');
      expect(dragged.gridX, isNot(startX), reason: 'the drag should have taken effect');

      expect(state.canUndoLayout, isTrue);
      state.undoLayout();
      expect(state.canUndoLayout, isFalse, reason: 'eight frames must be one undo step');

      final fan = state.furniture.firstWhere((f) => f.id == 'fan');
      expect(fan.gridX, startX);
      expect(fan.gridY, startY);
    });

    test('endFurnitureGesture without a drag is a no-op', () {
      final state = AppState();
      state.clearLayoutHistory();
      state.endFurnitureGesture();
      expect(state.canUndoLayout, isFalse);
    });
  });

  group('shipped presets', () {
    test('no preset starts with an overlap', () {
      for (final preset in RoomPreset.values) {
        final state = AppState();
        state.selectPreset(preset);
        final overlaps = state.layoutConflicts
            .where((c) => c.kind == LayoutConflictKind.overlap)
            .toList();
        expect(
          overlaps,
          isEmpty,
          reason: '${preset.name} ships overlapping items, which makes them undraggable: '
              '${overlaps.map((c) => c.itemIds).toList()}',
        );
      }
    });

    test('every preset item can actually be dragged somewhere', () {
      for (final preset in RoomPreset.values) {
        final state = AppState();
        state.selectPreset(preset);
        // Structural mounts (doors/windows/wall AC) stay locked until Invasive.
        state.setInvasiveEdit(true);
        for (final item in List.of(state.furniture)) {
          if (item.locked) continue;
          final startX = item.gridX;
          final startY = item.gridY;

          var moved = false;
          for (final step in const [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)]) {
            state.moveFurniture(item.id, startX + step.$1, startY + step.$2);
            final now = state.furniture.firstWhere((f) => f.id == item.id);
            if ((now.gridX - startX).abs() > 0.01 || (now.gridY - startY).abs() > 0.01) {
              moved = true;
              state.moveFurniture(item.id, startX, startY);
              break;
            }
          }
          expect(moved, isTrue, reason: '${preset.name}/${item.id} is stuck in place');
        }
      }
    });
  });

  group('2D floor plan', () {
    testWidgets('horizontal swipe on the plan no longer moves anything', (tester) async {
      final state = await pumpRig(tester);
      final before = {for (final f in state.furniture) f.id: (f.gridX, f.gridY)};

      // Empty floor, away from any item: this used to spin the whole room.
      final plan = find.byKey(const ValueKey('rig2d_bed'));
      final planCenter = tester.getCenter(plan);
      await tester.dragFrom(planCenter + const Offset(0, 160), const Offset(220, 0));
      await tester.pumpAndSettle();

      for (final f in state.furniture) {
        expect((f.gridX, f.gridY), before[f.id], reason: '${f.id} should not have moved');
      }
    });

    testWidgets('dragging an item follows the finger', (tester) async {
      final state = await pumpRig(tester);
      final fanBefore = state.furniture.firstWhere((f) => f.id == 'fan');

      await tester.drag(find.byKey(const ValueKey('rig2d_fan')), const Offset(0, -120));
      await tester.pumpAndSettle();

      final fanAfter = state.furniture.firstWhere((f) => f.id == 'fan');
      expect(
        fanAfter.gridY,
        lessThan(fanBefore.gridY),
        reason: 'dragging up should decrease the row',
      );
      expect(
        (fanAfter.gridX - fanBefore.gridX).abs(),
        lessThan(0.5),
        reason: 'a purely vertical drag should not slide the item sideways',
      );
    });
  });

  group('3D', () {
    testWidgets('drags the selected item across the floor', (tester) async {
      final state = await pumpRig(tester);

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();

      state.selectFurniture('fan');
      await tester.pumpAndSettle();
      final before = state.furniture.firstWhere((f) => f.id == 'fan');

      // Aim at the item where it actually renders in the 3D canvas.
      final canvasRect = tester.getRect(find.byKey(const ValueKey('rig3d_canvas')));
      final cam = CameraPose(
        roomWidth: state.currentRoomData.gridCols.toDouble(),
        roomDepth: state.currentRoomData.gridRows.toDouble(),
        roomHeight: 2.8,
        yaw: 0,
        pitch: 0.34,
        distance: 15,
      );
      final projected = RoomProjection.project(
        OrbitVec3(before.gridX + before.width / 2, 0.5, before.gridY + before.height / 2),
        canvasRect.size,
        cam,
      );
      expect(projected, isNotNull);
      final start = canvasRect.topLeft + projected!.offset;

      await tester.dragFrom(start, const Offset(0, 40));
      await tester.pumpAndSettle();

      final after = state.furniture.firstWhere((f) => f.id == 'fan');
      final moved = (after.gridX - before.gridX).abs() + (after.gridY - before.gridY).abs();
      expect(moved, greaterThan(0.05), reason: 'the selected item should have moved');
      expect(after.gridX, inInclusiveRange(0.0, state.currentRoomData.gridCols.toDouble()));
      expect(after.gridY, inInclusiveRange(0.0, state.currentRoomData.gridRows.toDouble()));
    });

    testWidgets('drag on empty floor orbits instead of moving furniture', (tester) async {
      final state = await pumpRig(tester);

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      state.clearSelection();
      await tester.pumpAndSettle();

      final before = {for (final f in state.furniture) f.id: (f.gridX, f.gridY)};
      final yawBefore = _readYawDegrees(tester);

      final canvasRect = tester.getRect(find.byKey(const ValueKey('rig3d_canvas')));
      await tester.dragFrom(canvasRect.center, const Offset(120, 0));
      await tester.pumpAndSettle();

      for (final f in state.furniture) {
        expect((f.gridX, f.gridY), before[f.id], reason: '${f.id} should not have moved');
      }
      expect(_readYawDegrees(tester), isNot(yawBefore));
    });
  });

  group('add-item sheet', () {
    testWidgets('adds a catalog item to the layout', (tester) async {
      final state = await pumpRig(tester);
      final countBefore = state.furniture.length;

      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();

      expect(find.text('Airflow'), findsWidgets);

      await tester.dragUntilVisible(
        find.text('Task Lamp'),
        find.byType(ListView).last,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task Lamp'));
      await tester.pumpAndSettle();

      expect(state.furniture.length, countBefore + 1);
      expect(state.furniture.any((f) => f.name == 'Task Lamp'), isTrue);
      expect(state.hasPendingPlacement, isTrue);
      expect(find.text('Place'), findsOneWidget);
    });

    testWidgets('add sheet only lists v1 catalog items', (tester) async {
      await pumpRig(tester);

      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();

      expect(find.text('UPGRADES'), findsNothing);
      expect(find.text('Smart Air Purifier'), findsNothing);
      expect(find.text('Monitor Arm'), findsNothing);
      expect(find.text('Cable Tray'), findsNothing);
      expect(find.text('PC Tower'), findsWidgets);
      expect(find.text('Wall AC'), findsWidgets);
    });
  });
}

/// Reads the yaw readout the 3D prints in its corner badge.
int _readYawDegrees(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.textContaining('yaw '))
      .map((t) => t.data ?? '')
      .firstWhere((d) => d.startsWith('yaw '));
  final match = RegExp(r'yaw (-?\d+)').firstMatch(text);
  return int.parse(match!.group(1)!);
}
