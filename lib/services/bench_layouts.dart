// lib/services/bench_layouts.dart
// What each Bench mode actually simulates.
//
// The Bench used to seed "My Rig" from a hand-authored demo layout and push it
// into the Rig, so every field and particle you saw described the sample room
// rather than yours. These layouts are derived from the live Rig furniture
// instead, and nothing here mutates app state.
import '../models/airflow_prototype.dart';
import '../models/ergonomics_prototype.dart';
import '../models/lighting_prototype.dart';
import '../models/room_model.dart';
import 'airflow_optimizer.dart';
import 'ergonomics_optimizer.dart';
import 'lighting_optimizer.dart';
import 'spatial_analyzer.dart';

enum BenchMode { airflow, lighting, ergonomics, spatial }

/// The Bench sits in an IndexedStack, so its panels keep building while the
/// user is dragging furniture on the Rig tab. Re-solving the fields on every
/// pointer frame of a drag we cannot even see is what would make dragging
/// stick, so the panels only resimulate while this tab is the visible one.
const int benchTabIndex = 3;

/// Which layout a Bench view is showing.
enum BenchLayoutKind {
  /// The furniture currently in the Rig.
  myRoom,

  /// [myRoom] after the mode's optimizer rearranges it.
  improved,

  /// The hand-authored reference room, kept for comparison.
  sample,
}

class BenchLayouts {
  final BenchMode mode;
  final List<FurnitureItem> myRoom;
  final List<FurnitureItem> improved;
  final List<FurnitureItem> sample;

  /// Why the optimizer moved what it moved, straight from the optimizer.
  final List<String> improvedReasons;

  /// True when the Rig had nothing to simulate and [myRoom] fell back to the
  /// reference room, so the UI can say so instead of implying it is yours.
  final bool fellBackToSample;

  /// Changes whenever the Rig furniture changes, used to trigger a re-sim.
  final String fingerprint;

  const BenchLayouts({
    required this.mode,
    required this.myRoom,
    required this.improved,
    required this.sample,
    required this.improvedReasons,
    required this.fellBackToSample,
    required this.fingerprint,
  });

  List<FurnitureItem> forKind(BenchLayoutKind kind) {
    switch (kind) {
      case BenchLayoutKind.myRoom:
        return myRoom;
      case BenchLayoutKind.improved:
        return improved;
      case BenchLayoutKind.sample:
        return sample;
    }
  }
}

class BenchLayoutBuilder {
  BenchLayoutBuilder._();

  /// Identifies a layout by the things the simulators care about: which items
  /// exist and where they sit.
  static String fingerprintOf(List<FurnitureItem> items) {
    final parts = items
        .map((f) => '${f.id}:${f.gridX.toStringAsFixed(2)},'
            '${f.gridY.toStringAsFixed(2)},'
            '${f.width.toStringAsFixed(2)},${f.height.toStringAsFixed(2)},'
            '${f.yawDegrees.toStringAsFixed(0)}')
        .toList()
      ..sort();
    return parts.join('|');
  }

  static List<FurnitureItem> sampleFor(BenchMode mode) {
    final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
    switch (mode) {
      case BenchMode.airflow:
        return AirflowPrototypeLayouts.baseline(source);
      case BenchMode.lighting:
        return LightingPrototypeLayouts.baseline(source);
      case BenchMode.ergonomics:
        return ErgonomicsPrototypeLayouts.baseline(source);
      case BenchMode.spatial:
        return source.map((f) => f.copyWith()).toList(growable: false);
    }
  }

  /// The reference room's improved counterpart, used only when there is no Rig
  /// furniture to optimize.
  static List<FurnitureItem> sampleImprovedFor(BenchMode mode) {
    final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
    switch (mode) {
      case BenchMode.airflow:
        return AirflowPrototypeLayouts.optimized(source);
      case BenchMode.lighting:
        return LightingPrototypeLayouts.optimized(source);
      case BenchMode.ergonomics:
        return ErgonomicsPrototypeLayouts.optimized(source);
      case BenchMode.spatial:
        return SpatialOptimizer.optimize(
          furniture: source,
          gridCols: 6,
          gridRows: 8,
        ).furniture;
    }
  }

  static BenchLayouts build({
    required BenchMode mode,
    required List<FurnitureItem> roomFurniture,
    required int gridCols,
    required int gridRows,
  }) {
    final live = roomFurniture
        .where((f) => !f.hidden)
        .map((f) => f.copyWith())
        .toList(growable: false);
    final sample = sampleFor(mode);
    final fellBack = live.isEmpty;
    final myRoom = fellBack ? sample : live;

    final (improved, reasons) = fellBack
        ? (sampleImprovedFor(mode), const <String>[])
        : _optimize(mode, myRoom, gridCols, gridRows);

    return BenchLayouts(
      mode: mode,
      myRoom: myRoom,
      improved: improved,
      sample: sample,
      improvedReasons: reasons,
      fellBackToSample: fellBack,
      fingerprint: fingerprintOf(myRoom),
    );
  }

  static (List<FurnitureItem>, List<String>) _optimize(
    BenchMode mode,
    List<FurnitureItem> furniture,
    int gridCols,
    int gridRows,
  ) {
    switch (mode) {
      case BenchMode.airflow:
        final r = AirflowOptimizer.optimize(
          furniture: furniture,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        return (r.furniture, r.reasons);
      case BenchMode.lighting:
        final r = LightingOptimizer.optimize(
          furniture: furniture,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        return (r.furniture, r.reasons);
      case BenchMode.ergonomics:
        final r = ErgonomicsOptimizer.optimize(
          furniture: furniture,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        return (r.furniture, r.reasons);
      case BenchMode.spatial:
        final r = SpatialOptimizer.optimize(
          furniture: furniture,
          gridCols: gridCols,
          gridRows: gridRows,
        );
        return (r.furniture, r.reasons);
    }
  }
}