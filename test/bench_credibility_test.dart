// Guards the promises the Bench tab makes to the user: a layout's score depends
// only on the layout, the improved prototypes really are improvements, the
// prototypes are physically valid, and the results badge matches its own checks.
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/airflow_prototype.dart';
import 'package:room_rig/models/ergonomics_prototype.dart';
import 'package:room_rig/models/lighting_prototype.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/airflow_simulator.dart';
import 'package:room_rig/services/benchmark_validator.dart';
import 'package:room_rig/services/ergonomics_simulator.dart';
import 'package:room_rig/services/layout_collision.dart';
import 'package:room_rig/services/lighting_simulator.dart';
import 'package:room_rig/widgets/benchmark_validation_card.dart';

void main() {
  final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
  final source = room.furniture;

  final airflowBase = AirflowPrototypeLayouts.baseline(source);
  final airflowOpt = AirflowPrototypeLayouts.optimized(source);
  final lightBase = LightingPrototypeLayouts.baseline(source);
  final lightOpt = LightingPrototypeLayouts.optimized(source);
  final ergoBase = ErgonomicsPrototypeLayouts.baseline(source);
  final ergoOpt = ErgonomicsPrototypeLayouts.optimized(source);

  BenchmarkValidation validate(List<FurnitureItem> furniture, String mode) {
    return BenchmarkValidator.validateLayout(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      mode: mode,
    );
  }

  group('scores depend on the layout, not on the optimized label', () {
    test('airflow', () {
      for (final layout in [airflowBase, airflowOpt]) {
        final off = AirflowSimulator.build(furniture: layout, optimized: false).metrics;
        final on = AirflowSimulator.build(furniture: layout, optimized: true).metrics;
        expect(on.circulationScore, closeTo(off.circulationScore, 0.001));
        expect(on.deadZoneRatio, closeTo(off.deadZoneRatio, 0.001));
      }
    });

    test('lighting', () {
      for (final layout in [lightBase, lightOpt]) {
        final off = LightingSimulator.build(furniture: layout, optimized: false).metrics;
        final on = LightingSimulator.build(furniture: layout, optimized: true).metrics;
        expect(on.exposureScore, closeTo(off.exposureScore, 0.001));
      }
    });

    test('ergonomics', () {
      for (final layout in [ergoBase, ergoOpt]) {
        final off = ErgonomicsSimulator.build(furniture: layout, optimized: false).metrics;
        final on = ErgonomicsSimulator.build(furniture: layout, optimized: true).metrics;
        expect(on.comfortScore, closeTo(off.comfortScore, 0.001));
      }
    });
  });

  group('the improved prototype genuinely beats the baseline', () {
    test('airflow circulation up and dead zones down', () {
      final b = AirflowSimulator.build(furniture: airflowBase, optimized: false).metrics;
      final o = AirflowSimulator.build(furniture: airflowOpt, optimized: true).metrics;
      expect(o.circulationScore, greaterThan(b.circulationScore));
      expect(o.deadZoneRatio, lessThan(b.deadZoneRatio));
    });

    test('lighting exposure up', () {
      final b = LightingSimulator.build(furniture: lightBase, optimized: false).metrics;
      final o = LightingSimulator.build(furniture: lightOpt, optimized: true).metrics;
      expect(o.exposureScore, greaterThan(b.exposureScore));
    });

    test('ergonomics comfort up', () {
      final b = ErgonomicsSimulator.build(furniture: ergoBase, optimized: false).metrics;
      final o = ErgonomicsSimulator.build(furniture: ergoOpt, optimized: true).metrics;
      expect(o.comfortScore, greaterThan(b.comfortScore));
    });
  });

  test('improved prototypes have no overlaps or blocked doorways', () {
    final layouts = {
      'airflow': airflowOpt,
      'lighting': lightOpt,
      'ergonomics': ergoOpt,
    };
    for (final e in layouts.entries) {
      final hard = LayoutCollision.findConflicts(
        furniture: e.value,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ).where((c) =>
          c.kind == LayoutConflictKind.overlap ||
          c.kind == LayoutConflictKind.blockedOpening);
      expect(hard, isEmpty, reason: '${e.key} improved layout: ${hard.map((c) => c.message)}');
    }
  });

  group('the results badge tells the truth', () {
    test('PASS is only shown when every check passes', () {
      final layouts = {
        'airflow': [airflowBase, airflowOpt],
        'lighting': [lightBase, lightOpt],
        'ergonomics': [ergoBase, ergoOpt],
      };
      for (final e in layouts.entries) {
        for (final layout in e.value) {
          final v = validate(layout, e.key);
          final allPass = v.checks.every((c) => c.status == BenchCheckStatus.pass);
          expect(v.verdict == BenchVerdict.pass, allPass,
              reason: '${e.key}: badge disagrees with its own check rows');
        }
      }
    });

    test('each improved prototype passes its own bench', () {
      expect(validate(airflowOpt, 'airflow').verdict, BenchVerdict.pass);
      expect(validate(lightOpt, 'lighting').verdict, BenchVerdict.pass);
      expect(validate(ergoOpt, 'ergonomics').verdict, BenchVerdict.pass);
    });

    test('each baseline prototype does not pass its own bench', () {
      expect(validate(airflowBase, 'airflow').verdict, isNot(BenchVerdict.pass));
      expect(validate(lightBase, 'lighting').verdict, isNot(BenchVerdict.pass));
      expect(validate(ergoBase, 'ergonomics').verdict, isNot(BenchVerdict.pass));
    });
  });
}
