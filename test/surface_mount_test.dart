import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/screens/rig_customizer_screen.dart';

FurnitureItem _item({
  required String id,
  String? name,
  String? icon,
  double x = 2,
  double y = 2,
  double w = 1,
  double h = 1,
}) {
  return FurnitureItem(
    id: id,
    name: name ?? id,
    iconName: icon ?? id,
    category: 'neutral',
    gridX: x,
    gridY: y,
    width: w,
    height: h,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  group('classification', () {
    test('windows, doors and vents mount to walls; furniture stays on the floor', () {
      SurfaceMount mount(FurnitureItem f) =>
          SurfaceMounts.of(f, gridCols: 6, gridRows: 8);

      expect(mount(_item(id: 'window', x: 2, y: 0)).surface, MountSurface.wall);
      expect(mount(_item(id: 'door', x: 0, y: 6)).surface, MountSurface.wall);
      expect(mount(_item(id: 'ac', name: 'AC Unit', x: 5, y: 0)).surface, MountSurface.wall);

      for (final id in const ['desk', 'chair', 'bed', 'pc', 'shelf', 'fan', 'sofa']) {
        expect(
          mount(_item(id: id)).surface,
          MountSurface.floor,
          reason: '$id should stay on the floor',
        );
      }
    });

    test('vent matching does not fire on unrelated names containing "ac"', () {
      for (final f in [
        _item(id: 'rack', name: 'Storage Rack', icon: 'shelf'),
        _item(id: 'chair2', name: 'Backrest Chair', icon: 'chair'),
        _item(id: 'mat', name: 'Anti-Fatigue Mat', icon: 'mat'),
        _item(id: 'tray', name: 'Cable Tray', icon: 'cableTray'),
      ]) {
        expect(SurfaceMounts.isVent(f), isFalse, reason: '${f.name} is not a vent');
      }

      expect(SurfaceMounts.isVent(_item(id: 'ac', name: 'AC Unit', icon: 'ac')), isTrue);
      expect(SurfaceMounts.isVent(_item(id: 'ac_2', name: 'AC Unit', icon: 'ac')), isTrue);
      expect(
        SurfaceMounts.isVent(_item(id: 'portable_ac', name: 'Portable AC', icon: 'ac')),
        isFalse,
        reason: 'floor portable AC is movable furniture, not a wall vent',
      );
      expect(
        SurfaceMounts.isVent(_item(id: 'split', name: 'Split Air Conditioner', icon: 'fan')),
        isTrue,
      );
    });

    test('mount heights match the volumes the simulators build', () {
      // AirflowSimulator._buildBoxes puts an AC at 1.4-2.3 and a window sink at
      // 0.9-2.1; drifting apart here would draw fittings where the physics has
      // nothing.
      final vent = SurfaceMounts.of(
        _item(id: 'ac', name: 'AC Unit', x: 5, y: 0),
        gridCols: 6,
        gridRows: 8,
      );
      expect(vent.bottomY, 1.4);
      expect(vent.topY, 2.3);

      final window = SurfaceMounts.of(_item(id: 'window', x: 2, y: 0), gridCols: 6, gridRows: 8);
      expect(window.bottomY, 0.9);
      expect(window.topY, 2.1);

      final door = SurfaceMounts.of(_item(id: 'door', x: 0, y: 6), gridCols: 6, gridRows: 8);
      expect(door.bottomY, 0);
      expect(door.topY, 2.1);
      expect(door.occupiesFloor, isFalse);
    });
  });

  group('wall selection', () {
    test('picks the wall the fitting actually sits against', () {
      RoomWall wall(double x, double y, {double w = 1, double h = 1}) =>
          SurfaceMounts.nearestWall(
            _item(id: 'window', x: x, y: y, w: w, h: h),
            gridCols: 6,
            gridRows: 8,
          );

      expect(wall(2, 0), RoomWall.north);
      expect(wall(2, 7), RoomWall.south);
      expect(wall(0, 3), RoomWall.west);
      expect(wall(5, 3), RoomWall.east);
    });

    test('span runs along the wall and points into the room', () {
      final north = SurfaceMounts.spanFor(
        _item(id: 'window', x: 2, y: 0, w: 2),
        gridCols: 6,
        gridRows: 8,
      );
      expect(north.wall, RoomWall.north);
      expect(north.z0, 0);
      expect(north.z1, 0);
      expect(north.x0, 2);
      expect(north.x1, 4);
      expect(north.inwardZ, 1, reason: 'north wall faces into increasing z');

      final east = SurfaceMounts.spanFor(
        _item(id: 'window', x: 5, y: 3),
        gridCols: 6,
        gridRows: 8,
      );
      expect(east.wall, RoomWall.east);
      expect(east.x0, 6, reason: 'seated on the far wall plane');
      expect(east.inwardX, -1);
    });

    test('every shipped preset fitting resolves to the wall it touches', () {
      for (final preset in RoomPreset.values) {
        final state = AppState();
        state.selectPreset(preset);
        final cols = state.currentRoomData.gridCols;
        final rows = state.currentRoomData.gridRows;

        for (final f in state.furniture) {
          final mount = SurfaceMounts.of(f, gridCols: cols, gridRows: rows);
          if (!mount.isWall) continue;
          final span = mount.span!;
          final touches = switch (span.wall) {
            RoomWall.north => f.gridY == 0,
            RoomWall.south => f.gridY + f.height == rows,
            RoomWall.west => f.gridX == 0,
            RoomWall.east => f.gridX + f.width == cols,
          };
          expect(
            touches,
            isTrue,
            reason: '${preset.name}/${f.id} is drawn on ${span.wall} but does not touch it',
          );
        }
      }
    });
  });

  group('staying seated', () {
    test('snapToWall pulls an off-wall fitting back and leaves furniture alone', () {
      final drifted = _item(id: 'window', x: 2, y: 1.5);
      final seated = SurfaceMounts.snapToWall(drifted, gridCols: 6, gridRows: 8);
      expect(seated.gridY, 0);
      expect(seated.gridX, 2, reason: 'sliding along the wall is preserved');

      final desk = _item(id: 'desk', x: 2, y: 1.5);
      expect(
        identical(SurfaceMounts.snapToWall(desk, gridCols: 6, gridRows: 8), desk),
        isTrue,
      );
    });

    test('dragging a window inward re-seats it on its wall', () {
      final state = AppState();
      state.setInvasiveEdit(true);
      final before = state.furniture.firstWhere((f) => f.id == 'window');
      expect(before.gridY, 0);

      state.moveFurniture('window', before.gridX, 3.0);
      final after = state.furniture.firstWhere((f) => f.id == 'window');
      expect(after.gridY, 0, reason: 'a window cannot float in the middle of the room');
    });

    test('dragging a window sideways slides it along the wall', () {
      final state = AppState();
      state.setInvasiveEdit(true);
      final before = state.furniture.firstWhere((f) => f.id == 'window');

      state.moveFurniture('window', before.gridX + 1, before.gridY);
      final after = state.furniture.firstWhere((f) => f.id == 'window');
      expect(after.gridX, isNot(before.gridX));
      expect(after.gridY, 0);
    });

    test('dragging a fitting across the room re-seats it on the nearest wall', () {
      final state = AppState();
      state.setInvasiveEdit(true);
      final rows = state.currentRoomData.gridRows;

      state.moveFurniture('window', 2, rows - 1);
      final after = state.furniture.firstWhere((f) => f.id == 'window');
      expect(after.gridY + after.height, rows, reason: 'should seat on the far wall');
    });
  });

  group('floor space', () {
    test('a wall vent does not block furniture underneath it', () {
      final state = AppState();
      final ac = state.furniture.firstWhere((f) => f.id == 'ac');

      // Slide the shelf under the AC head.
      state.moveFurniture('shelf', ac.gridX, ac.gridY);
      final shelf = state.furniture.firstWhere((f) => f.id == 'shelf');
      expect(shelf.gridX, ac.gridX);
      expect(shelf.gridY, ac.gridY);
      expect(
        state.layoutConflicts.any(
          (c) => c.itemIds.contains('ac') && c.itemIds.contains('shelf'),
        ),
        isFalse,
        reason: 'a wall unit at 1.4-2.3 m is not a floor obstruction',
      );
    });
  });

  group('desk top', () {
    test('monitor on a desk mounts to the work surface; PC beside it stays on the floor', () {
      final desk = _item(id: 'desk', x: 2, y: 2, w: 2);
      final monitor = _item(id: 'monitor', name: 'Monitor', icon: 'monitor', x: 2, y: 2);
      final pc = _item(id: 'pc', name: 'PC Tower', icon: 'pc', x: 4, y: 2);
      final furniture = [desk, monitor, pc];

      expect(
        SurfaceMounts.of(monitor, gridCols: 6, gridRows: 8, furniture: furniture).surface,
        MountSurface.desk,
      );
      expect(
        SurfaceMounts.of(pc, gridCols: 6, gridRows: 8, furniture: furniture).surface,
        MountSurface.floor,
      );
    });

    test('floor lamp is not a desktop item; task lamp is', () {
      expect(
        SurfaceMounts.isDeskTopItem(_item(id: 'floor_lamp', name: 'Floor Lamp', icon: 'floorLamp')),
        isFalse,
      );
      expect(
        SurfaceMounts.isDeskTopItem(_item(id: 'lamp', name: 'Task Lamp', icon: 'lamp')),
        isTrue,
      );
    });

    test('snapOntoHost seats a lamp on the desk', () {
      final desk = _item(id: 'desk', x: 2, y: 2, w: 2);
      final lamp = _item(id: 'lamp', name: 'Task Lamp', icon: 'lamp', x: 1.75, y: 2);
      final seated = SurfaceMounts.snapOntoHost(lamp, [desk, lamp]);
      expect(seated.gridX, greaterThanOrEqualTo(2));
      expect(seated.gridX + seated.width, lessThanOrEqualTo(4.001));
      expect(seated.gridY, 2);
    });
  });

  group('cutaway view', () {
    test('only the walls behind the room are drawn', () {
      // Camera parked on the +z side, looking toward -z.
      const eyeX = 3.0;
      const eyeZ = 18.0;
      bool far(RoomWall w) =>
          SurfaceMounts.wallIsFarSide(w, eyeX, eyeZ, roomWidth: 6, roomDepth: 8);

      expect(far(RoomWall.north), isTrue, reason: 'far wall stays visible');
      expect(far(RoomWall.south), isFalse, reason: 'near wall must be cut away');
      expect(far(RoomWall.west), isTrue);
      expect(far(RoomWall.east), isTrue);
    });

    test('orbiting to the other side swaps which wall is cut away', () {
      bool far(RoomWall w, double x, double z) =>
          SurfaceMounts.wallIsFarSide(w, x, z, roomWidth: 6, roomDepth: 8);

      expect(far(RoomWall.north, 3, -10), isFalse);
      expect(far(RoomWall.south, 3, -10), isTrue);
    });
  });

  group('rig canvas', () {
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

    testWidgets('wall fittings render against their wall, not as floor cells', (tester) async {
      await pumpRig(tester);

      final plan = tester.getRect(find.byKey(const ValueKey('rig2d_bed')));
      final window = tester.getRect(find.byKey(const ValueKey('rig2d_window')));
      final door = tester.getRect(find.byKey(const ValueKey('rig2d_door')));

      // The bed is a floor cell somewhere in the middle; the window hugs the
      // top edge and the door hugs the left edge of the same canvas.
      expect(window.top, lessThan(plan.top));
      expect(window.left, greaterThan(0));
      expect(door.left, lessThan(plan.left));
    });

    testWidgets('tapping the wall AC in 3D selects it', (tester) async {
      final state = await pumpRig(tester);

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      state.clearSelection();
      await tester.pumpAndSettle();

      // Sweep the canvas for the AC: it is only reachable if the pick uses the
      // wall geometry rather than a floor box.
      final rect = tester.getRect(find.byKey(const ValueKey('rig3d_canvas')));
      var found = false;
      for (double fx = 0.55; fx <= 0.95 && !found; fx += 0.02) {
        for (double fy = 0.1; fy <= 0.6 && !found; fy += 0.02) {
          await tester.tapAt(Offset(
            rect.left + rect.width * fx,
            rect.top + rect.height * fy,
          ));
          await tester.pump();
          if (state.selectedItemId == 'ac') found = true;
        }
      }
      expect(found, isTrue, reason: 'the wall AC should be tappable where it is drawn');
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
