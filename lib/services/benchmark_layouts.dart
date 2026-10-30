// lib/services/benchmark_layouts.dart
// What each Benchmark mode actually simulates.
//
// Pair: left source vs right source (Current Room / checkpoint / Auto-Rig).
// When a side is Auto-Rig, it is optimized from the other side's inventory.
import '../models/room_model.dart';
import 'multi_objective_optimizer.dart';

// The Benchmark sits in an IndexedStack, so its panels keep building while the
// user is dragging furniture on the Room tab. Re-solving the fields on every
// pointer frame of a drag we cannot even see is what would make dragging
// stick, so the panels only resimulate while `benchmarkTabIndex` is visible.
export '../models/app_tabs.dart' show benchmarkTabIndex;

enum BenchmarkMode { airflow, lighting, ergonomics, spatial }

/// Which layout a Benchmark view is showing.
enum BenchmarkLayoutKind {
  /// Left compare source (Current Room / baseline).
  currentRoom,

  /// Right compare source (Auto-Rig or other picked layout).
  autoRig,
}

class BenchmarkLayouts {
  final BenchmarkMode mode;
  final List<FurnitureItem> currentRoom;
  final List<FurnitureItem> autoRig;

  /// Why the optimizer moved what it moved (when right is Auto-Rig).
  final List<String> autoRigReasons;

  /// True when left inventory is empty — never invent a reference room.
  final bool isEmpty;

  final String fingerprint;

  final MultiObjectiveWeights weights;

  final String rankLabel;
  final int candidateCount;
  final int alternateIndex;
  final int requestedAlternateIndex;

  final String leftCaption;
  final String rightCaption;
  final bool rightIsAutoRig;

  const BenchmarkLayouts({
    required this.mode,
    required this.currentRoom,
    required this.autoRig,
    required this.autoRigReasons,
    required this.isEmpty,
    required this.fingerprint,
    required this.weights,
    this.rankLabel = '',
    this.candidateCount = 1,
    this.alternateIndex = 0,
    this.requestedAlternateIndex = 0,
    this.leftCaption = 'Current Room',
    this.rightCaption = 'Auto-Rig',
    this.rightIsAutoRig = true,
  });

  String get weightsCacheKey => weights.cacheKey;

  String get weightsSummary => weights.summaryLabel;

  /// Chip / banner line for the right variant.
  String get autoRigCaption {
    final mix = weightsSummary;
    if (isEmpty) {
      return '$rightCaption — create a room first · $mix';
    }
    if (rightIsAutoRig && rankLabel.isNotEmpty) return '$rankLabel · $mix';
    if (rightIsAutoRig) return '$rightCaption · $mix';
    return rightCaption;
  }

  bool get canTryAlternate =>
      rightIsAutoRig && candidateCount > 1 && !isEmpty;

  List<FurnitureItem> forKind(BenchmarkLayoutKind kind) {
    switch (kind) {
      case BenchmarkLayoutKind.currentRoom:
        return currentRoom;
      case BenchmarkLayoutKind.autoRig:
        return autoRig;
    }
  }
}

class BenchmarkLayoutBuilder {
  BenchmarkLayoutBuilder._();

  static const defaultWeights = MultiObjectiveWeights(
    airflow: 0.7,
    lighting: 0.7,
    ergonomics: 0.7,
  );

  static final Map<String, List<MultiObjectiveResult>> _candidateCache = {};

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

  /// Build left vs right layouts.
  ///
  /// [leftFurniture] is the resolved left inventory. When empty, both sides stay
  /// empty and [BenchmarkLayouts.isEmpty] is true — callers must show an empty
  /// state (never load a reference room silently).
  /// When [rightIsAutoRig] is true, right is optimized from [autoRigSeed] (usually left).
  /// Otherwise [rightFurniture] is used as-is.
  static BenchmarkLayouts build({
    required BenchmarkMode mode,
    required List<FurnitureItem> roomFurniture,
    required int gridCols,
    required int gridRows,
    List<FurnitureItem>? leftFurniture,
    List<FurnitureItem>? rightFurniture,
    bool rightIsAutoRig = true,
    List<FurnitureItem>? autoRigSeed,
    String leftCaption = 'Current Room',
    String rightCaption = 'Auto-Rig',
    /// Legacy: treated as left when [leftFurniture] is null.
    List<FurnitureItem>? baselineFurniture,
    MultiObjectiveWeights weights = defaultWeights,
    int alternateIndex = 0,
  }) {
    final leftSrc = leftFurniture ??
        ((baselineFurniture != null && baselineFurniture.isNotEmpty)
            ? baselineFurniture
            : roomFurniture);
    final live = leftSrc
        .where((f) => !f.hidden)
        .map((f) => f.copyWith())
        .toList(growable: false);
    final empty = live.isEmpty;
    final current = live;
    final w = weights.normalized();
    final seed = (autoRigSeed != null && autoRigSeed.isNotEmpty)
        ? autoRigSeed
            .where((f) => !f.hidden)
            .map((f) => f.copyWith())
            .toList(growable: false)
        : current;
    final fp =
        '${fingerprintOf(current)}|${rightIsAutoRig ? 'ar' : fingerprintOf(rightFurniture ?? const [])}|${fingerprintOf(seed)}';

    if (empty) {
      return BenchmarkLayouts(
        mode: mode,
        currentRoom: const [],
        autoRig: const [],
        autoRigReasons: const <String>[
          'No furniture yet — create or stock a room before Benchmark can score.',
        ],
        isEmpty: true,
        fingerprint: fp,
        weights: w,
        leftCaption: leftCaption,
        rightCaption: rightCaption,
        rightIsAutoRig: rightIsAutoRig,
        requestedAlternateIndex: alternateIndex,
      );
    }

    if (!rightIsAutoRig) {
      final right = (rightFurniture == null || rightFurniture.isEmpty)
          ? current
          : rightFurniture
              .where((f) => !f.hidden)
              .map((f) => f.copyWith())
              .toList(growable: false);
      return BenchmarkLayouts(
        mode: mode,
        currentRoom: current,
        autoRig: right,
        autoRigReasons: const [],
        isEmpty: false,
        fingerprint: fp,
        weights: w,
        leftCaption: leftCaption,
        rightCaption: rightCaption,
        rightIsAutoRig: false,
        requestedAlternateIndex: alternateIndex,
      );
    }

    final ranked = _candidatesFor(
      furniture: seed,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: w,
      fingerprint: fingerprintOf(seed),
    );
    final count = ranked.length;
    final idx = count <= 0 ? 0 : alternateIndex % count;
    final pick = count == 0
        ? MultiObjectiveOptimizer.optimize(
            furniture: seed,
            gridCols: gridCols,
            gridRows: gridRows,
            weights: w,
          )
        : ranked[idx];

    return BenchmarkLayouts(
      mode: mode,
      currentRoom: current,
      autoRig: pick.furniture,
      autoRigReasons: pick.reasons,
      isEmpty: false,
      fingerprint: fp,
      weights: w,
      rankLabel: pick.rankLabel,
      candidateCount: count.clamp(1, 99),
      alternateIndex: idx,
      requestedAlternateIndex: alternateIndex,
      leftCaption: leftCaption,
      rightCaption: rightCaption,
      rightIsAutoRig: true,
    );
  }

  static List<MultiObjectiveResult> _candidatesFor({
    required List<FurnitureItem> furniture,
    required int gridCols,
    required int gridRows,
    required MultiObjectiveWeights weights,
    required String fingerprint,
  }) {
    final key = '$fingerprint|${weights.cacheKey}|${gridCols}x$gridRows';
    final hit = _candidateCache[key];
    if (hit != null) return hit;
    final ranked = MultiObjectiveOptimizer.optimizeCandidates(
      furniture: furniture,
      gridCols: gridCols,
      gridRows: gridRows,
      weights: weights,
    );
    _candidateCache[key] = ranked;
    if (_candidateCache.length > 12) {
      _candidateCache.remove(_candidateCache.keys.first);
    }
    return ranked;
  }
}
