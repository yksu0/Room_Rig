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

  test('toggleUpgrade pending drops a centre ghost until cancel', () {
    final state = AppState();
    final before = state.furniture.length;

    expect(state.toggleUpgrade(0, pending: true), isTrue);
    expect(state.hasPendingPlacement, isTrue);
    expect(state.furniture.length, before + 1);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isTrue);
    expect(state.upgrades.first['added'], isTrue);

    state.cancelPendingPlacement();
    expect(state.hasPendingPlacement, isFalse);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isFalse);
    expect(state.upgrades.first['added'], isFalse);
  });

  test('leaving Rig cancels an unfinished Place ghost', () {
    final state = AppState();
    state.setTab(2);
    expect(state.toggleUpgrade(0, pending: true), isTrue);
    expect(state.hasPendingPlacement, isTrue);

    state.setTab(0);
    expect(state.hasPendingPlacement, isFalse);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isFalse);
    expect(state.upgrades.first['added'], isFalse);
  });

  test('jumping to Rig with a pending upgrade keeps the ghost', () {
    final state = AppState();
    state.setTab(4);
    expect(state.toggleUpgrade(0, pending: true), isTrue);
    state.setTab(2);
    expect(state.hasPendingPlacement, isTrue);
    expect(state.furniture.any((f) => f.id == 'upg_fan'), isTrue);
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
