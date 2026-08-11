// lib/services/benchmark_validator.dart
// Geometry-based pass/fail checks against the live layout (not slider guesses).
import '../models/room_model.dart';
import 'airflow_optimizer.dart';
import 'ergonomics_optimizer.dart';
import 'layout_collision.dart';
import 'lighting_optimizer.dart';

enum BenchCheckStatus { pass, warn, fail }

class BenchCheck {
  final String id;
  final String label;
  final String detail;
  final BenchCheckStatus status;
  final double value;
  final double threshold;

  const BenchCheck({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
    required this.value,
    required this.threshold,
  });
}

class BenchmarkValidation {
  final String mode; // airflow | lighting | ergonomics | overall
  final List<BenchCheck> checks;
  final bool passed;
  final double score;

  const BenchmarkValidation({
    required this.mode,
    required this.checks,
    required this.passed,
    required this.score,
  });

  int get passCount => checks.where((c) => c.status == BenchCheckStatus.pass).length;
  int get failCount => checks.where((c) => c.status == BenchCheckStatus.fail).length;
}

class BenchmarkValidator {
  BenchmarkValidator._();

  static const airflowPass = 62.0;
  static const lightingPass = 55.0;
  static const ergonomicsPass = 58.0;
  static const deadZoneMax = 0.28;
  static const glareMax = 0.55;
  static const pathMin = 0.45;
  static const conflictMax = 0;

  static BenchmarkValidation validateLayout({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    String mode = 'overall',
  }) {
    if (furniture.isEmpty) {
      return const BenchmarkValidation(
        mode: 'overall',
        checks: [
          BenchCheck(
            id: 'empty',
            label: 'Layout populated',
            detail: 'No furniture in the active room layout',
            status: BenchCheckStatus.fail,
            value: 0,
            threshold: 1,
          ),
        ],
        passed: false,
        score: 0,
      );
    }

    final air = AirflowOptimizer.evaluate(furniture);
    final light = LightingOptimizer.evaluate(furniture);
    final ergo = ErgonomicsOptimizer.evaluate(furniture);
    final conflicts = LayoutCollision.findConflicts(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    final hardConflicts = conflicts
        .where((c) =>
            c.kind == LayoutConflictKind.overlap ||
            c.kind == LayoutConflictKind.blockedOpening)
        .length;

    final checks = <BenchCheck>[];

    void addAir() {
      checks.add(
        BenchCheck(
          id: 'circulation',
          label: 'Circulation score',
          detail: air.circulationScore >= airflowPass
              ? 'Airflow paths clear enough for the room'
              : 'Circulation is below the ${airflowPass.toInt()} pass mark',
          status: air.circulationScore >= airflowPass
              ? BenchCheckStatus.pass
              : (air.circulationScore >= airflowPass - 10
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: air.circulationScore,
          threshold: airflowPass,
        ),
      );
      checks.add(
        BenchCheck(
          id: 'dead_zones',
          label: 'Dead zone ratio',
          detail: air.deadZoneRatio <= deadZoneMax
              ? 'Stagnant pockets are within tolerance'
              : 'Too much of the room is stuck / under-circulated',
          status: air.deadZoneRatio <= deadZoneMax
              ? BenchCheckStatus.pass
              : BenchCheckStatus.fail,
          value: air.deadZoneRatio * 100,
          threshold: deadZoneMax * 100,
        ),
      );
    }

    void addLight() {
      checks.add(
        BenchCheck(
          id: 'exposure',
          label: 'Exposure score',
          detail: light.exposureScore >= lightingPass
              ? 'Task zone gets enough useful light'
              : 'Desk lighting / daylight exposure is too low',
          status: light.exposureScore >= lightingPass
              ? BenchCheckStatus.pass
              : (light.exposureScore >= lightingPass - 10
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: light.exposureScore,
          threshold: lightingPass,
        ),
      );
      checks.add(
        BenchCheck(
          id: 'glare',
          label: 'Glare risk',
          detail: light.glareRisk <= glareMax
              ? 'Desk is not square-on to harsh daylight'
              : 'Desk faces the window too directly — glare risk',
          status: light.glareRisk <= glareMax
              ? BenchCheckStatus.pass
              : BenchCheckStatus.warn,
          value: light.glareRisk * 100,
          threshold: glareMax * 100,
        ),
      );
    }

    void addErgo() {
      checks.add(
        BenchCheck(
          id: 'comfort',
          label: 'Comfort score',
          detail: ergo.comfortScore >= ergonomicsPass
              ? 'Clearances and reach are in a workable range'
              : 'Desk/chair/path comfort is below the pass mark',
          status: ergo.comfortScore >= ergonomicsPass
              ? BenchCheckStatus.pass
              : (ergo.comfortScore >= ergonomicsPass - 10
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: ergo.comfortScore,
          threshold: ergonomicsPass,
        ),
      );
      checks.add(
        BenchCheck(
          id: 'paths',
          label: 'Walk-path quality',
          detail: ergo.pathScore >= pathMin
              ? 'Frequent routes can navigate the room'
              : 'High-traffic paths are blocked or heavily detoured',
          status: ergo.pathScore >= pathMin
              ? BenchCheckStatus.pass
              : BenchCheckStatus.fail,
          value: ergo.pathScore * 100,
          threshold: pathMin * 100,
        ),
      );
    }

    void addGeometry() {
      checks.add(
        BenchCheck(
          id: 'conflicts',
          label: 'Layout conflicts',
          detail: hardConflicts == 0
              ? 'No overlaps or blocked openings'
              : '$hardConflicts hard conflict${hardConflicts == 1 ? '' : 's'} in the layout',
          status: hardConflicts == 0 ? BenchCheckStatus.pass : BenchCheckStatus.fail,
          value: hardConflicts.toDouble(),
          threshold: conflictMax.toDouble(),
        ),
      );
    }

    switch (mode) {
      case 'airflow':
        addAir();
        addGeometry();
        break;
      case 'lighting':
        addLight();
        addGeometry();
        break;
      case 'ergonomics':
        addErgo();
        addGeometry();
        break;
      default:
        addAir();
        addLight();
        addErgo();
        addGeometry();
    }

    final score = switch (mode) {
      'airflow' => air.circulationScore,
      'lighting' => light.exposureScore,
      'ergonomics' => ergo.comfortScore,
      _ => (air.circulationScore + light.exposureScore + ergo.comfortScore) / 3,
    };

    final passed = checks.every((c) => c.status != BenchCheckStatus.fail) &&
        checks.any((c) => c.status == BenchCheckStatus.pass);

    return BenchmarkValidation(
      mode: mode,
      checks: checks,
      passed: passed,
      score: score.clamp(0, 100),
    );
  }
}
