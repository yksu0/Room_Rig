import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/surface_mount.dart';
import 'package:room_rig/services/airflow_simulator.dart';

void main() {
  FurnitureItem item({
    required String id,
    required String name,
    required String icon,
    double yaw = 0,
    double x = 2,
    double y = 2,
  }) {
    return FurnitureItem(
      id: id,
      name: name,
      category: 'airflow',
      iconName: icon,
      gridX: x,
      gridY: y,
      width: 1,
      height: 1,
      yawDegrees: yaw,
      airflowImpact: 0,
      lightingImpact: 0,
      ergonomicsImpact: 0,
      cost: 0,
    );
  }

  test('portable AC is cold + floor-standing, not a wall vent', () {
    final f = item(id: 'portable_ac', name: 'Portable AC', icon: 'ac', yaw: 90);
    expect(SurfaceMounts.isVent(f), isFalse);
    expect(SurfaceMounts.isStructuralMount(f), isFalse);

    final sim = AirflowSimulator.build(furniture: [f], optimized: false);
    final ac = sim.boxes.singleWhere((b) => b.kind == 'ac');
    expect(ac.directional, isTrue);
    expect(ac.strength, lessThan(1.0));
    expect(ac.min.y, lessThan(0.5), reason: 'floor unit, not wall band');
    expect(ac.yawDegrees, 90);
  });

  test('wall AC stays a structural vent with room-center throw', () {
    final f = item(id: 'ac', name: 'Wall AC', icon: 'ac', x: 5, y: 1);
    expect(SurfaceMounts.isVent(f), isTrue);

    final sim = AirflowSimulator.build(furniture: [f], optimized: false);
    final ac = sim.boxes.singleWhere((b) => b.kind == 'ac');
    expect(ac.directional, isFalse);
    expect(ac.strength, 1.0);
    expect(ac.min.y, greaterThan(1.0));
  });

  test('space heater is directional heat; radiator is wide plume heat', () {
    final heater = item(id: 'space_heater', name: 'Space Heater', icon: 'floorLamp', yaw: 180);
    final rad = item(id: 'radiator', name: 'Radiator', icon: 'kitchen', x: 1, y: 1);

    final sim = AirflowSimulator.build(furniture: [heater, rad], optimized: false);
    final hot = sim.boxes.where((b) => b.kind == 'heat').toList();
    expect(hot, hasLength(2));

    final h = hot.firstWhere((b) => b.id == 'space_heater');
    final r = hot.firstWhere((b) => b.id == 'radiator');
    expect(h.directional, isTrue);
    expect(h.yawDegrees, 180);
    expect(r.directional, isFalse);
    expect(r.strength, greaterThan(h.strength));
  });

  test('console and mini fridge are milder heat than NAS', () {
    final sim = AirflowSimulator.build(
      furniture: [
        item(id: 'console', name: 'Gaming Console', icon: 'gaming'),
        item(id: 'mini_fridge', name: 'Mini Fridge', icon: 'kitchen', x: 3),
        item(id: 'nas', name: 'NAS / Server', icon: 'pc', x: 4),
      ],
      optimized: false,
    );
    final byId = {for (final b in sim.boxes) b.id: b};
    expect(byId['console']!.kind, 'heat');
    expect(byId['mini_fridge']!.kind, 'heat');
    expect(byId['nas']!.kind, 'heat');
    expect(byId['nas']!.strength, greaterThan(byId['console']!.strength));
    expect(byId['nas']!.strength, greaterThan(byId['mini_fridge']!.strength));
  });

  test('fan yaw drives aim instead of always room center', () {
    final fan = item(id: 'fan', name: 'Stand Fan', icon: 'fan', yaw: 90, x: 1, y: 1);
    final sim = AirflowSimulator.build(furniture: [fan], optimized: false);
    final box = sim.boxes.singleWhere((b) => b.kind == 'fan');
    expect(box.directional, isTrue);
    expect(box.yawDegrees, 90);

    final aim = AirflowSimulator.fanAimDirection(box, 0);
    // 90° yawAim is +X; at t=0 sweep is 0 so aim.x should dominate.
    expect(aim.x.abs(), greaterThan(aim.z.abs()));
  });

  test('evaporative cooler is soft cold jet', () {
    final f = item(id: 'evaporative', name: 'Evaporative Cooler', icon: 'purifier');
    expect(SurfaceMounts.isVent(f), isFalse);
    final sim = AirflowSimulator.build(furniture: [f], optimized: false);
    final ac = sim.boxes.singleWhere((b) => b.kind == 'ac');
    expect(ac.directional, isTrue);
    expect(ac.strength, lessThan(0.7));
  });

  test('window is passive until intake or exhaust unbalances the room', () {
    final window = item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0);
    final ac = item(id: 'ac', name: 'Wall AC', icon: 'ac', x: 5, y: 1);

    final acOnly = AirflowSimulator.build(furniture: [ac, window], optimized: false);
    final opening = acOnly.boxes.singleWhere((b) => b.kind == 'opening');
    expect(opening.leakSign, 0);

    final pressurized = AirflowSimulator.build(
      furniture: [
        ac,
        window,
        item(id: 'intake', name: 'Intake Vent', icon: 'intake', x: 4, y: 0),
      ],
      optimized: false,
    );
    final leaking = pressurized.boxes.singleWhere((b) => b.kind == 'opening');
    expect(leaking.leakSign, greaterThan(0));
    expect(pressurized.boxes.any((b) => b.kind == 'intake'), isTrue);
    final intake = pressurized.boxes.singleWhere((b) => b.kind == 'intake');
    expect(
      leaking.strength,
      closeTo(intake.strength * AirflowSimulator.openingLeakFraction, 0.02),
    );
    expect(leaking.strength, lessThan(intake.strength * 0.4));
  });

  test('negative pressure makes the window leak in, still weaker than the exhaust', () {
    final sim = AirflowSimulator.build(
      furniture: [
        item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0),
        item(id: 'exhaust', name: 'Exhaust Fan', icon: 'exhaust', x: 5, y: 1),
      ],
      optimized: false,
    );
    final opening = sim.boxes.singleWhere((b) => b.kind == 'opening');
    final exhaust = sim.boxes.singleWhere((b) => b.kind == 'exhaust');
    expect(opening.leakSign, lessThan(0));
    expect(opening.strength, closeTo(exhaust.strength * AirflowSimulator.openingLeakFraction, 0.02));
    expect(opening.strength, lessThan(exhaust.strength * 0.4));
  });

  test('balanced intake and exhaust leaves the window idle', () {
    final sim = AirflowSimulator.build(
      furniture: [
        item(id: 'window', name: 'Window', icon: 'window', x: 0, y: 0),
        item(id: 'intake', name: 'Intake Vent', icon: 'intake', x: 4, y: 0),
        item(id: 'exhaust', name: 'Exhaust Fan', icon: 'exhaust', x: 1, y: 6),
      ],
      optimized: false,
    );
    final opening = sim.boxes.singleWhere((b) => b.kind == 'opening');
    expect(opening.leakSign, 0);
    expect(opening.strength, 0);
  });

  test('exhaust and intake classify as wall vents, not floor fans', () {
    final intake = item(id: 'intake', name: 'Intake Vent', icon: 'intake', x: 0, y: 0);
    final exhaust = item(id: 'exhaust', name: 'Exhaust Fan', icon: 'exhaust', x: 3, y: 0);
    expect(SurfaceMounts.isIntake(intake), isTrue);
    expect(SurfaceMounts.isExhaust(exhaust), isTrue);
    expect(SurfaceMounts.isVent(intake), isFalse);

    final sim = AirflowSimulator.build(furniture: [intake, exhaust], optimized: false);
    expect(sim.boxes.where((b) => b.kind == 'intake'), hasLength(1));
    expect(sim.boxes.where((b) => b.kind == 'exhaust'), hasLength(1));
  });
}
