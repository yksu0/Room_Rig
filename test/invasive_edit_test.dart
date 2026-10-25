import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/models/room_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  test('doors windows vents and ceiling lights are structural mounts', () {
    FurnitureItem f(String id, String icon) => FurnitureItem(
          id: id,
          name: id,
          iconName: icon,
          category: 'neutral',
          gridX: 1,
          gridY: 1,
        );

    expect(SurfaceMounts.isStructuralMount(f('door', 'door')), isTrue);
    expect(SurfaceMounts.isStructuralMount(f('window', 'window')), isTrue);
    expect(SurfaceMounts.isStructuralMount(f('ac', 'ac')), isTrue);
    expect(SurfaceMounts.isStructuralMount(f('ceil', 'ceilingLight')), isTrue);
    expect(SurfaceMounts.isStructuralMount(f('desk', 'desk')), isFalse);
    expect(SurfaceMounts.isStructuralMount(f('lamp', 'lamp')), isFalse);
    expect(SurfaceMounts.isStructuralMount(f('fan', 'fan')), isFalse);
  });

  test('lock blocks move for any item; unlocked doors slide on walls', () {
    final state = AppState()..selectPreset(RoomPreset.gamingSetup);
    expect(state.invasiveEdit, isFalse);

    final door = state.furniture.firstWhere((f) => f.iconName == 'door');
    final desk = state.furniture.firstWhere((f) => f.iconName == 'desk');
    final doorY = door.gridY;
    final deskX = desk.gridX;

    state.toggleFurnitureLock(desk.id);
    state.moveFurniture(desk.id, deskX + 1.0, desk.gridY);
    expect(
      state.furniture.firstWhere((f) => f.id == desk.id).gridX,
      deskX,
      reason: 'locked desk must not move',
    );

    expect(door.locked, isFalse);
    state.moveFurniture(door.id, door.gridX, doorY + 1.0);
    expect(
      state.furniture.firstWhere((f) => f.id == door.id).gridY,
      isNot(doorY),
      reason: 'unlocked door should slide while non-invasive',
    );
  });

  test('unlocked window slides along its wall without invasive', () {
    final state = AppState()..selectPreset(RoomPreset.gamingSetup);
    expect(state.invasiveEdit, isFalse);

    final window = state.furniture.firstWhere((f) => f.iconName == 'window');
    expect(window.locked, isFalse);
    final before = window.gridX;
    state.moveFurniture(window.id, before + 1.0, window.gridY);
    expect(
      state.furniture.firstWhere((f) => f.id == window.id).gridX,
      isNot(before),
    );
  });

  test('wall AC cannot be deleted unless invasive', () {
    final state = AppState()..selectPreset(RoomPreset.gamingSetup);
    final ac = state.furniture.firstWhere((f) => f.iconName == 'ac');
    expect(state.deleteFurniture(ac.id), isFalse);
    expect(state.furniture.any((f) => f.id == ac.id), isTrue);

    state.setInvasiveEdit(true);
    expect(state.deleteFurniture(ac.id), isTrue);
    expect(state.furniture.any((f) => f.id == ac.id), isFalse);
  });
}
