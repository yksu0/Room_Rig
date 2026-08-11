import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hide / lock / duplicate / delete furniture actions', () {
    final state = AppState();
    final beforeCount = state.furniture.length;

    state.toggleFurnitureHidden('lamp');
    expect(state.furniture.firstWhere((f) => f.id == 'lamp').hidden, isTrue);
    expect(state.furniture.firstWhere((f) => f.id == 'lamp').statusLabel, 'Hidden');

    state.toggleFurnitureLock('chair');
    expect(state.furniture.firstWhere((f) => f.id == 'chair').locked, isTrue);

    final chairBefore = state.furniture.firstWhere((f) => f.id == 'chair');
    state.moveFurniture('chair', chairBefore.gridX + 1, chairBefore.gridY);
    final chairAfter = state.furniture.firstWhere((f) => f.id == 'chair');
    expect(chairAfter.gridX, chairBefore.gridX); // locked blocks move

    expect(state.duplicateFurniture('lamp'), isTrue);
    expect(state.furniture.length, beforeCount + 1);
    expect(state.furniture.any((f) => f.id.startsWith('lamp_copy')), isTrue);
    expect(state.selectedItemId?.startsWith('lamp_copy'), isTrue);

    expect(state.deleteFurniture('door'), isFalse); // openings protected
    expect(state.deleteFurniture('lamp'), isTrue);
    expect(state.furniture.any((f) => f.id == 'lamp'), isFalse);
  });
}
