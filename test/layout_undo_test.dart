import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/services/layout_collision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppState layout undo', () {
    test('undo restores furniture after move gesture', () async {
      final state = AppState();
      // Let restore attempt settle against the mock prefs.
      await Future<void>.delayed(Duration.zero);

      final before = state.furniture.firstWhere((f) => f.id == 'fan');
      final beforeX = before.gridX;
      final beforeY = before.gridY;

      state.beginFurnitureGesture();
      state.moveFurniture('fan', 0.0, 7.0);
      expect(state.furniture.firstWhere((f) => f.id == 'fan').gridY, 7.0);
      expect(state.canUndoLayout, isTrue);

      state.endFurnitureGesture();
      state.undoLayout();
      final after = state.furniture.firstWhere((f) => f.id == 'fan');
      expect(after.gridX, beforeX);
      expect(after.gridY, beforeY);
      expect(state.canRedoLayout, isTrue);

      state.redoLayout();
      expect(state.furniture.firstWhere((f) => f.id == 'fan').gridY, 7.0);
    });

    test('collision prevents overlapping desk and chair', () async {
      final state = AppState();
      await Future<void>.delayed(Duration.zero);
      final desk = state.furniture.firstWhere((f) => f.id == 'desk');
      state.beginFurnitureGesture();
      state.moveFurniture('chair', desk.gridX + 0.5, desk.gridY);
      expect(state.dragPoseBlocked, isTrue);
      state.endFurnitureGesture();
      final chair = state.furniture.firstWhere((f) => f.id == 'chair');
      final deskAfter = state.furniture.firstWhere((f) => f.id == 'desk');
      expect(LayoutCollision.overlaps(chair, deskAfter), isFalse);
    });
  });
}
