import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_simulator.dart';

void main() {
  FurnitureItem item({
    required String id,
    required String name,
    required String icon,
    double x = 1,
    double y = 1,
  }) {
    return FurnitureItem(
      id: id,
      name: name,
      category: 'neutral',
      iconName: icon,
      gridX: x,
      gridY: y,
      width: 1,
      height: 1,
      airflowImpact: 0,
      lightingImpact: 0,
      ergonomicsImpact: 0,
      cost: 0,
    );
  }

  test('no AC and no PC means no cold/hot thermal particles', () {
    final sim = AirflowSimulator.build(
      furniture: [
        item(id: 'door', name: 'Door', icon: 'door', x: 0, y: 5),
        item(id: 'window', name: 'Window', icon: 'window', x: 3, y: 0),
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 4, y: 4),
      ],
      optimized: false,
    );

    final thermal = sim.particles.where((p) => !p.isAmbient).toList();
    expect(thermal, isEmpty, reason: 'ghost AC/PC plumes should not spawn');
    expect(sim.particles.where((p) => p.isAmbient), isNotEmpty);
  });

  test('AC spawns cold particles at the AC, PC spawns hot at the PC', () {
    final sim = AirflowSimulator.build(
      furniture: [
        item(id: 'ac', name: 'AC Unit', icon: 'ac', x: 5, y: 1),
        item(id: 'pc', name: 'PC Tower', icon: 'pc', x: 1, y: 3),
        item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0),
      ],
      optimized: false,
    );

    final cold = sim.particles.where((p) => !p.isAmbient && p.isCold).toList();
    final hot = sim.particles.where((p) => !p.isAmbient && !p.isCold).toList();
    expect(cold, isNotEmpty);
    expect(hot, isNotEmpty);

    // Cold parcels start near the AC, not a hardcoded corner.
    final coldNearAc = cold.where((p) => (p.position.x - 5.5).abs() < 1.5).length;
    expect(coldNearAc, greaterThan(cold.length ~/ 2));

    final hotNearPc = hot.where((p) => (p.position.x - 1.5).abs() < 1.5).length;
    expect(hotNearPc, greaterThan(hot.length ~/ 2));
  });

  test('field has no cold bias without an AC', () {
    final withAc = AirflowSimulator.build(
      furniture: [
        item(id: 'ac', name: 'AC Unit', icon: 'ac', x: 5, y: 1),
        item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0),
      ],
      optimized: false,
    );
    final without = AirflowSimulator.build(
      furniture: [
        item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0),
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 3, y: 3),
      ],
      optimized: false,
    );

    double coldMass(AirflowSimSnapshot s) =>
        s.field.temperature.where((t) => t < -0.05).fold<double>(0, (a, b) => a + b.abs());

    expect(coldMass(withAc), greaterThan(coldMass(without) + 1.0));
  });
}
