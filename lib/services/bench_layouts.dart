// lib/services/bench_layouts.dart
// What each Bench mode actually simulates.
//
// Improved arrangement is the SAME across airflow / lighting / ergonomics /
// spatial — one Auto-Rig under the live Rig weight mix. Only the scored field
// (sim) changes per mode. Try alternate cycles the same candidate pool Rig uses.
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

  /// [myRoom] after Auto-Rig rearranges it (same pose for every mode).
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

  /// Weight mix used for Improved (matches Rig Auto-Rig sliders).
  final MultiObjectiveWeights weights;

  /// e.g. `Best of 4 · 84` — empty when a fallback pack was used.
  final String rankLabel;

  /// How many diverse Auto-Rig candidates were available.
  final int candidateCount;

  /// Which ranked candidate is shown (0-based, after modulo).
  final int alternateIndex;

  /// Raw cursor from AppState before modulo (for cache invalidation).
  final int requestedAlternateIndex;

  const BenchLayouts({
    required this.mode,
    required this.myRoom,
    required this.improved,
    required this.sample,
    required this.improvedReasons,
    required this.fellBackToSample,
    required this.fingerprint,
    required this.weights,
    this.rankLabel = '',
    this.candidateCount = 1,
    this.alternateIndex = 0,
    this.requestedAlternateIndex = 0,
  });

  String get weightsCacheKey => weights.cacheKey;

  String get weightsSummary => weights.summaryLabel;

  /// Chip / banner line for the Improved variant.
  String get improvedCaption {
    final mix = weightsSummary;
    if (fellBackToSample) {
      return 'Improved — reference room (Rig empty) · $mix';
    }
    if (rankLabel.isNotEmpty) return '$rankLabel · $mix';
    return 'Improved · $mix';
  }

  bool get canTryAlternate => candidateCount > 1 && !fellBackToSample;

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

  /// Default when callers omit weights (tests / legacy) — matches prior balanced mix.
  static const defaultWeights = MultiObjectiveWeights(
    airflow: 0.7,
    lighting: 0.7,
    ergonomics: 0.7,
  );

  /// Cache of ranked Auto-Rig candidates keyed by room fp + weight mix.
  static final Map<String, List<MultiObjectiveResult>> _candidateCache = {};

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

  static void clearCandidateCache() => _candidateCache.clear();

  /// One shared reference room for every Bench mode (not mode-specific demos).
  static List<FurnitureItem> sampleFor(BenchMode mode) {
    return RoomPresets.getPreset(RoomPreset.gamingSetup)
        .furniture
        .map((f) => f.copyWith())
        .toList(growable: false);
  }

  /// Reference-room Improved under [weights] (empty-Rig fallback only).
  static List<FurnitureItem> sampleImprovedFor(
    BenchMode mode, {
    MultiObjectiveWeights weights = defaultWeights,
  }) {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    return MultiObjectiveOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: weights,
    ).furniture;
  }

  static BenchLayouts build({
    required BenchMode mode,
    required List<FurnitureItem> roomFurniture,
    required int gridCols,
    required int gridRows,
    MultiObjectiveWeights weights = defaultWeights,
    int alternateIndex = 0,
  }) {
    final live = roomFurniture
        .where((f) => !f.hidden)
        .map((f) => f.copyWith())
        .toList(growable: false);
    final sample = sampleFor(mode);
    final fellBack = live.isEmpty;
    final myRoom = fellBack ? sample : live;
    final w = weights.normalized();
    final fp = fingerprintOf(myRoom);

    if (fellBack) {
      final ranked = _candidatesFor(
        furniture: myRoom,
        gridCols: gridCols,
        gridRows: gridRows,
        weights: w,
        fingerprint: fp,
      );
      final pick = ranked.isEmpty
          ? null
          : ranked[alternateIndex.clamp(0, ranked.length - 1) % ranked.length];
      return BenchLayouts(
        mode: mode,
        myRoom: myRoom,
        improved: pick?.furniture ??
            sampleImprovedFor(mode, weights: w),
        sample: sample,
        improvedReasons: pick?.reasons ??
            const <String>['Auto-Rig on the reference room (Rig was empty)'],
        fellBackToSample: true,
        fingerprint: fp,
        weights: w,
        rankLabel: pick?.rankLabel ?? '',
        candidateCount: ranked.length.clamp(1, 99),
        alternateIndex: 0,
        requestedAlternateIndex: alternateIndex,
      );
    }

    final ranked = _candidatesFor(
      furniture: myRoom,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: w,
      fingerprint: fp,
    );
    final count = ranked.length;
    final idx = count <= 0 ? 0 : alternateIndex % count;
    final pick = count == 0
        ? MultiObjectiveOptimizer.optimize(
            furniture: myRoom,
            gridCols: gridCols,
            gridRows: gridRows,
            weights: w,
          )
        : ranked[idx];

    return BenchLayouts(
      mode: mode,
      myRoom: myRoom,
      improved: pick.furniture,
      sample: sample,
      improvedReasons: pick.reasons,
      fellBackToSample: false,
      fingerprint: fp,
      weights: w,
      rankLabel: pick.rankLabel,
      candidateCount: count.clamp(1, 99),
      alternateIndex: idx,
      requestedAlternateIndex: alternateIndex,
    );
  }

  static List<MultiObjectiveResult> _candidatesFor({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
    required String fingerprint,
  }) {
    final key =
        '$fingerprint|${weights.cacheKey}|${gridCols}x$gridRows';
    final hit = _candidateCache[key];
    if (hit != null) return hit;
    final ranked = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    _candidateCache[key] = ranked;
    // Bound memory — drop oldest when large.
    if (_candidateCache.length > 12) {
      _candidateCache.remove(_candidateCache.keys.first);
    }
    return ranked;
  }
}
