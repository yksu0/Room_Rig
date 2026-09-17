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

  test('non-invasive mode blocks moving structural mounts but not floor items', () {
    final state = AppState();
    expect(state.invasiveEdit, isFalse);

    final door = state.furniture.firstWhere((f) => f.iconName == 'door');
    final desk = state.furniture.firstWhere((f) => f.iconName == 'desk');
    final doorX = door.gridX;
    final deskX = desk.gridX;

    state.moveFurniture(door.id, doorX + 1.5, door.gridY);
    expect(
      state.furniture.firstWhere((f) => f.id == door.id).gridX,
      doorX,
      reason: 'door should stay put while non-invasive',
    );

    state.moveFurniture(desk.id, deskX + 1.0, desk.gridY);
    expect(
      state.furniture.firstWhere((f) => f.id == desk.id).gridX,
      isNot(deskX),
      reason: 'desk should still move',
    );
  });

  test('invasive mode unlocks structural mounts for dragging', () {
    final state = AppState();
    state.setInvasiveEdit(true);

    final window = state.furniture.firstWhere((f) => f.iconName == 'window');
    final before = window.gridX;
    // Slide along the north wall.
    state.moveFurniture(window.id, before + 1.0, window.gridY);
    expect(
      state.furniture.firstWhere((f) => f.id == window.id).gridX,
      isNot(before),
    );
  });

  test('wall AC cannot be deleted unless invasive', () {
    final state = AppState();
    // Gaming setup includes an AC.
    final ac = state.furniture.firstWhere((f) => f.iconName == 'ac');
    expect(state.deleteFurniture(ac.id), isFalse);
    expect(state.furniture.any((f) => f.id == ac.id), isTrue);

    state.setInvasiveEdit(true);
    expect(state.deleteFurniture(ac.id), isTrue);
    expect(state.furniture.any((f) => f.id == ac.id), isFalse);
  });
}
