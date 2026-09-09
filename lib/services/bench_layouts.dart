// lib/services/bench_layouts.dart
// What each Bench mode actually simulates.
//
// The Bench used to seed "My Rig" from a hand-authored demo layout and push it
// into the Rig, so every field and particle you saw described the sample room
// rather than yours. These layouts are derived from the live Rig furniture
// instead, and nothing here mutates app state.
//
// Improved arrangement is the SAME across airflow / lighting / ergonomics /
// spatial — one balanced Auto-Rig. Only the scored field (sim) changes per mode.
import '../models/room_model.dart';
import 'multi_objective_optimizer.dart';

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

  /// [myRoom] after balanced Auto-Rig rearranges it (same pose for every mode).
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

  /// Shared balanced weights so every Bench mode's Improved is identical.
  static const improvedWeights = MultiObjectiveWeights(
    airflow: 0.7,
    lighting: 0.7,
    ergonomics: 0.7,
  );

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

  /// One shared reference room for every Bench mode (not mode-specific demos).
  static List<FurnitureItem> sampleFor(BenchMode mode) {
    return RoomPresets.getPreset(RoomPreset.gamingSetup)
        .furniture
        .map((f) => f.copyWith())
        .toList(growable: false);
  }

  /// The reference room's improved counterpart, used only when there is no Rig
  /// furniture to optimize — same balanced Auto-Rig as live Improved.
  static List<FurnitureItem> sampleImprovedFor(BenchMode mode) {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    return MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: improvedWeights,
    ).furniture;
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
        ? (
            sampleImprovedFor(mode),
            const <String>['Balanced Auto-Rig on the reference room'],
          )
        : _optimizeShared(myRoom, gridCols, gridRows);

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

  /// One arrangement for every Bench mode — balanced MultiObjective Auto-Rig.
  /// Mode only changes which simulator scores the layout.
  static (List<FurnitureItem>, List<String>) _optimizeShared(
    List<FurnitureItem> furniture,
    int gridCols,
    int gridRows,
  ) {
    final r = MultiObjectiveOptimizer.optimize(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: improvedWeights,
    );
    return (r.furniture, r.reasons);
  }
}
