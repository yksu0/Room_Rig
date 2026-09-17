import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/ergonomics_simulator.dart';
import 'package:room_rig/services/lighting_simulator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FurnitureItem item({
    required String id,
    required String name,
    required String icon,
    String category = 'neutral',
    double x = 1,
    double y = 1,
    double w = 1,
    double h = 1,
  }) {
    return FurnitureItem(
      id: id,
      name: name,
      category: category,
      iconName: icon,
      gridX: x,
      gridY: y,
      width: w,
      height: h,
      airflowImpact: 0,
      lightingImpact: 0,
      ergonomicsImpact: 0,
      cost: 0,
    );
  }

  test('lighting does not invent a ghost window', () {
    final sim = LightingSimulator.build(
      furniture: [
        item(id: 'door', name: 'Door', icon: 'door', x: 0, y: 5),
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 3, y: 3, w: 2, h: 1),
        item(id: 'lamp', name: 'Task Lamp', icon: 'lamp', x: 3.2, y: 3.1),
      ],
      optimized: false,
    );

    expect(sim.lights.any((l) => l.kind == 'window'), isFalse);
    expect(sim.metrics.daylightReach, 0);
    expect(sim.metrics.glareRisk, 0);
    expect(sim.lights.any((l) => l.kind == 'ceiling'), isTrue);
    expect(sim.lights.any((l) => l.kind == 'lamp'), isTrue);
  });

  test('lighting daylight only scores when a window exists', () {
    final withWindow = LightingSimulator.build(
      furniture: [
        item(id: 'window', name: 'Window', icon: 'window', x: 2, y: 0, w: 2),
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 2, y: 3, w: 2, h: 1),
      ],
      optimized: false,
    );
    final without = LightingSimulator.build(
      furniture: [
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 2, y: 3, w: 2, h: 1),
      ],
      optimized: false,
    );

    expect(withWindow.metrics.daylightReach, greaterThan(0));
    expect(without.metrics.daylightReach, 0);
  });

  test('ergonomics does not flag desk+monitor as a conflict', () {
    final sim = ErgonomicsSimulator.build(
      furniture: [
        item(id: 'desk', name: 'Desk', icon: 'desk', x: 2, y: 3, w: 2, h: 1),
        item(id: 'monitor', name: 'Monitor', icon: 'monitor', x: 2.4, y: 3.1, w: 1, h: 0.5),
        item(id: 'chair', name: 'Chair', icon: 'chair', x: 2.5, y: 4.2),
        item(id: 'door', name: 'Door', icon: 'door', x: 0, y: 6),
      ],
      optimized: false,
    );

    expect(sim.metrics.conflictRatio, 0);
    expect(sim.zones.where((z) => z.kind == 'conflict'), isEmpty);
  });

  test('ergonomics finds catalog-style desk/chair ids', () {
    final sim = ErgonomicsSimulator.build(
      furniture: [
        item(id: 'desk_2', name: 'Standing Desk', icon: 'desk', x: 2, y: 3, w: 2, h: 1),
        item(id: 'chair_copy', name: 'Office Chair', icon: 'chair', x: 2.5, y: 4.2),
        item(id: 'pc_tower', name: 'PC Tower', icon: 'pc', x: 2.1, y: 3.1),
      ],
      optimized: false,
    );

    expect(sim.metrics.deskAlign, greaterThan(0.35));
    expect(sim.reachCircle, isNotNull);
  });

  test('bench calibration asset documents heuristic models', () async {
    final raw = await rootBundle.loadString('assets/bench/calibration.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json['version'], 1);
    final domains = json['domains'] as Map<String, dynamic>;
    expect(domains['lighting']['inventGhostWindow'], isFalse);
    expect(domains['ergonomics']['deskTopItemsCountAsConflicts'], isFalse);
    expect(domains['airflow']['not'], contains('CFD'));
  });
}
