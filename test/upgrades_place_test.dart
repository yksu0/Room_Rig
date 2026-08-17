import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('toggleUpgrade places and removes a fan on the Rig', () {
    final state = AppState();
    final before = state.furniture.length;
    expect(state.upgrades.first['added'], isFalse);

    expect(state.toggleUpgrade(0), isTrue);
    expect(state.upgrades.first['added'], isTrue);
    expect(state.furniture.length, before + 1);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isTrue);

    expect(state.toggleUpgrade(0), isTrue);
    expect(state.upgrades.first['added'], isFalse);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isFalse);
  });

  test('FurnitureItem JSON round-trips upgrade fields', () {
    final item = FurnitureItem(
      id: 'upg_fan',
      name: 'Air Circulator Fan',
      iconName: 'fan',
      category: 'airflow',
      gridX: 4.25,
      gridY: 5.5,
      airflowImpact: 0.75,
    );
    final copy = FurnitureItem.fromJson(item.toJson());
    expect(copy.id, 'upg_fan');
    expect(copy.gridX, 4.25);
    expect(copy.airflowImpact, 0.75);
  });
}
