// lib/services/benchmark_validator.dart
// Geometry-based pass/fail checks against the live layout (not slider guesses).
import '../models/room_model.dart';
import '../models/room_scale.dart';
import 'airflow_optimizer.dart';
import 'ergonomics_optimizer.dart';
import 'layout_collision.dart';
import 'lighting_optimizer.dart';
import 'spatial_analyzer.dart';

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

  /// True when overlaps or blocked openings fail the layout geometry check.
  bool get hasHardLayoutConflicts {
    for (final c in checks) {
      if (c.id == 'conflicts' && c.status == BenchCheckStatus.fail) return true;
    }
    return false;
  }
}

class BenchmarkValidator {
  BenchmarkValidator._();

  // Bars are calibrated against each simulator's observed range for this room
  // size, so they sit between a clearly bad arrangement and a clearly good one.
  // They are not reachable by simply relabelling a layout as "optimized".
  // Calibrated against the 6×8 voxel sim on the gaming reference room:
  // a strong rearrange lands ~55 circulation / ~0.66 dead ratio; the cluttered
  // baseline sits ~54 / ~0.71. Bars sit between those observed values.
  static const airflowPass = 55.0;
  static const lightingPass = 45.0; // exposure saturates near 48 in this model
  static const ergonomicsPass = 58.0;
  static const deadZoneMax = 0.695;
  static const glareMax = 0.55;
  static const pathMin = 0.45;
  static const conflictMax = 0;
  static const walkableMin = 0.35;
  static const aisleMinCells = 1.0;
  static const spatialUtilPass = 55.0;

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
    final spatial = mode == 'spatial'
        ? SpatialAnalyzer.evaluate(
            furniture: furniture,
            gridCols: gridCols,
            gridRows: gridRows,
          )
        : null;
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

    void addSpatial() {
      final s = spatial!;
      checks.add(
        BenchCheck(
          id: 'walkable',
          label: 'Walkable floor',
          detail: s.walkableRatio >= walkableMin
              ? '${(s.walkableRatio * 100).round()}% of the floor is walkable'
              : 'Only ${(s.walkableRatio * 100).round()}% walkable — aisles are too tight',
          status: s.walkableRatio >= walkableMin
              ? BenchCheckStatus.pass
              : (s.walkableRatio >= walkableMin - 0.08
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: s.walkableRatio * 100,
          threshold: walkableMin * 100,
        ),
      );
      checks.add(
        BenchCheck(
          id: 'aisle',
          label: 'Largest aisle',
          detail: s.largestAisleCells >= aisleMinCells
              ? 'Largest walkway is about ${RoomScale.formatCellsAsMeters(s.largestAisleCells)}'
              : 'Largest walkway is under ${RoomScale.formatCellsAsMeters(aisleMinCells)} — too tight',
          status: s.largestAisleCells >= aisleMinCells
              ? BenchCheckStatus.pass
              : (s.largestAisleCells >= aisleMinCells - 0.25
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: s.largestAisleCells,
          threshold: aisleMinCells,
        ),
      );
      checks.add(
        BenchCheck(
          id: 'utilization',
          label: 'Floor utilization',
          detail: s.utilizationScore >= spatialUtilPass
              ? 'Floor use is in a workable range — not too empty or packed'
              : 'Floor is under-used or over-packed for comfortable walkways',
          status: s.utilizationScore >= spatialUtilPass
              ? BenchCheckStatus.pass
              : (s.utilizationScore >= spatialUtilPass - 10
                  ? BenchCheckStatus.warn
                  : BenchCheckStatus.fail),
          value: s.utilizationScore,
          threshold: spatialUtilPass,
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
      case 'spatial':
        addSpatial();
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
      'spatial' => spatial!.overallScore,
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
