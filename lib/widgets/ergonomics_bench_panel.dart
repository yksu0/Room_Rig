// lib/widgets/ergonomics_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/sim_room_bounds.dart';
import '../services/bench_layouts.dart';
import '../services/ergonomics_simulator.dart';
import '../services/layout_share_image.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'bench_panel_scaffold.dart';
import 'bench_room_views.dart';
import 'chrome/bench_results_chrome.dart';
import 'ergonomics_field_painter.dart';
import 'glass_card.dart';
import 'room_icons.dart';

enum _ErgoStep { layout, simulate, results }
enum _View { twoD, threeD, compare }

class ErgonomicsBenchPanel extends StatefulWidget {
  final ValueChanged<bool>? onOrbitDraggingChanged;

  const ErgonomicsBenchPanel({super.key, this.onOrbitDraggingChanged});

  @override
  State<ErgonomicsBenchPanel> createState() => _ErgonomicsBenchPanelState();
}

class _ErgonomicsBenchPanelState extends State<ErgonomicsBenchPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  _ErgoStep _step = _ErgoStep.layout;
  BenchLayoutKind _layoutVariant = BenchLayoutKind.myRoom;
  BenchLayoutKind _simVariant = BenchLayoutKind.myRoom;
  _View _roomView = _View.twoD;
  ErgonomicsVizMode _simViz = ErgonomicsVizMode.topDown2D;

  bool _orbitDragging = false;
  int _layoutOrbitResetNonce = 0;
  int _simOrbitResetNonce = 0;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.7;
  static const _defaultPitch = 0.4;
  static const _defaultDistance = 16.0;

  bool _showResults = false;
  bool _ready = false;
  bool _showPaths = true;

  BenchLayouts? _layouts;
  String? _layoutSyncKey;
  int _seenFocusToken = 0;
  ErgonomicsSimSnapshot? _myRoomSim;
  ErgonomicsSimSnapshot? _improvedSim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The bench reads the Rig; opening this tab must never write to it.
      _rebuild();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _rebuild() {
    _recompute(context.read<AppState>());
    if (mounted) setState(() {});
  }

  /// Rebuilds the reach and clearance fields from the furniture in the Rig.
  /// Safe to call during build: it only touches fields.
  void _recompute(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final left =
        state.resolveBenchCompareFurniture(state.benchCompareLeft) ?? const [];
    final rightIsAuto = state.benchCompareRight.isAutoRig;
    final right = rightIsAuto
        ? null
        : state.resolveBenchCompareFurniture(state.benchCompareRight);
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.ergonomics,
      roomFurniture: state.committedFurniture,
      leftFurniture: left,
      rightFurniture: right,
      rightIsAutoRig: rightIsAuto,
      autoRigSeed: state.benchAutoRigSeedFurniture(forRight: true),
      leftCaption: state.benchCompareSourceLabel(state.benchCompareLeft),
      rightCaption: state.benchCompareSourceLabel(state.benchCompareRight),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: state.optimizeWeights,
      alternateIndex: state.benchAlternateCursor,
    );
    _layouts = layouts;
    final bounds = SimRoomBounds.fromRoomData(room);
    _myRoomSim = ErgonomicsSimulator.build(furniture: layouts.myRoom, optimized: false, bounds: bounds);
    _improvedSim = ErgonomicsSimulator.build(furniture: layouts.improved, optimized: true, bounds: bounds);
    _ready = true;
    if (resetStep) {
      _step = _ErgoStep.layout;
      // A pending focus request (the Rig's "Sim Prototype" button) wins once;
      // after that a reset lands back on the user's own room.
      final pending = state.benchLayoutFocusToken != _seenFocusToken;
      var kind = pending ? state.benchLayoutFocus : BenchLayoutKind.myRoom;
      if (kind == BenchLayoutKind.sample) kind = BenchLayoutKind.myRoom;
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = kind;
      _simVariant = kind;
      _showResults = false;
    }
  }

  /// Picks up Rig edits so the reach zones always describe the current room.
  /// Called from build, so it must not call setState.
  void _syncFromState(AppState state) {
    _syncPulseForTab(state);
    if (state.currentTab != benchTabIndex) return;
    if (state.benchLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchLayoutFocusToken;
      var kind = state.benchLayoutFocus;
      if (kind == BenchLayoutKind.sample) kind = BenchLayoutKind.myRoom;
      _layoutVariant = kind;
      _simVariant = kind;
      _selectedFurnitureId = null;
    }
    final key =
        '${benchCompareFingerprint(state)}|${state.optimizeWeights.cacheKey}|${state.benchAlternateCursor}';
    if (_layouts != null && _layoutSyncKey == key) return;
    _layoutSyncKey = key;
    _recompute(state, resetStep: false);
  }

  void _syncPulseForTab(AppState state) {
    final onBench = state.currentTab == benchTabIndex;
    if (onBench) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  List<FurnitureItem> _furnitureFor(BenchLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  List<FurnitureItem> _layoutFurnitureFor(AppState state) => _furnitureFor(_layoutVariant);

  int get _stepIndex => switch (_step) {
        _ErgoStep.layout => benchStepLayout,
        _ErgoStep.simulate => benchStepMiddle,
        _ErgoStep.results => benchStepResults,
      };

  _ErgoStep _stepFromIndex(int i) => switch (i) {
        benchStepLayout => _ErgoStep.layout,
        benchStepMiddle => _ErgoStep.simulate,
        _ => _ErgoStep.results,
      };

  String get _layoutHint => _layouts?.fellBackToSample ?? false
      ? 'No baseline — this runs on the reference room. Add furniture in Rig, then Set baseline.'
      : 'Scores Baseline vs Auto-Rig (same engine as Rig Tools → Auto-Rig). Apply writes Auto-Rig onto your Rig.';

  ErgonomicsSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case BenchLayoutKind.improved:
        return _improvedSim;
      case BenchLayoutKind.sample:
      case BenchLayoutKind.myRoom:
        return _myRoomSim;
    }
  }

  List<String> _notesFor(BenchLayoutKind kind) {
    switch (kind) {
      case BenchLayoutKind.myRoom:
        if (_layouts?.fellBackToSample ?? false) {
          return const [
            'No baseline — showing the reference room',
            'Add furniture on Rig, then Set baseline (Compare)',
          ];
        }
        return const [
          'Pinned Baseline inventory for this lot',
          'Rig edits do not move Baseline until you Set baseline again',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that sits better than Baseline']
            : reasons;
      case BenchLayoutKind.sample:
        return const [
          'Reference room used to sanity-check the simulator',
          'Chair jammed against the desk with no pull-back space',
        ];
    }
  }

  /// Switching layouts only changes what is displayed — it never writes to the
  /// Rig. Pushing a layout back is the explicit Apply action under the results.
  void _setLayoutVariant(BenchLayoutKind next) {
    if (_layoutVariant == next) return;
    HapticFeedback.selectionClick();
    setState(() {
      _layoutVariant = next;
      _selectedFurnitureId = null;
    });
  }

  void _runBench() {
    // Sims are sync — open Results on Improved immediately.
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _showResults = true;
      _step = _ErgoStep.results;
      _simVariant = BenchLayoutKind.improved;
      _layoutVariant = BenchLayoutKind.improved;
      _roomView = _View.compare;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_ready) _syncFromState(state);
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.ergonomicsColor)),
      );
    }

    final applyValidation = _validationForSimVariant(state);
    final noOp = improvedLayoutIsNoOp(_layouts);
    final applyBlocked = noOp || applyValidation.hasHardLayoutConflicts;

    Future<void> applyImproved() async {
      if (!await confirmBenchApply(
        context,
        validation: applyValidation,
        fellBackToSample: _layouts?.fellBackToSample ?? false,
      )) {
        return;
      }
      if (!context.mounted) return;
      final before = List<FurnitureItem>.from(state.committedFurniture);
      state.applyFurnitureLayout(
        _furnitureFor(BenchLayoutKind.improved),
        markOptimized: true,
        lockMode: 'ergonomics',
      );
      final diff = summarizeLayoutDiff(before, state.furniture);
      final why = summarizeWhyWins(_layouts?.improvedReasons ?? const []);
      final room = state.currentRoomData;
      final after = List<FurnitureItem>.from(state.furniture);
      showBenchApplySnackBar(
        context,
        message: why.isEmpty ? 'Ergonomics applied · $diff' : 'Ergonomics applied · $diff · $why',
        accentColor: AppColors.ergonomicsColor,
        onOpenRig: () => state.setTab(2),
        onKeepAsBaseline: () => state.keepAppliedAsBenchBaseline(),
        onShareImage: () => LayoutShareImage.shareBeforeAfter(
          gridCols: room.gridCols,
          gridRows: room.gridRows,
          before: before,
          after: after,
          footer: why.isEmpty ? diff : '$diff · $why',
        ),
      );
    }

    final resultsExtra = noOp
        ? benchImprovedNoOpBanner(
            message:
                'Auto-Rig matches Baseline — paths are already as good as the optimizer found.',
          )
        : benchWhyWinsCard(
            reasons: _layouts?.improvedReasons ?? const [],
            accentColor: AppColors.ergonomicsColor,
          );

    return BenchPanelScaffold(
      accentColor: AppColors.ergonomicsColor,
      step: _stepIndex,
      stepLabels: const ['1. Layout', '2. Paths', '3. Results'],
      resultsEnabled: _showResults,
      running: false,
      onStepChanged: (i) => setState(() => _step = _stepFromIndex(i)),
      layoutBody: _layoutSection(state),
      layoutRunAction: BenchRunAction(
        buttonLabel: 'RUN ERGONOMICS BENCH',
        icon: RoomSvg.scan,
        onRun: _runBench,
        hint: _layoutHint,
      ),
      middleBody: _simSection(state),
      resultsExtra: resultsExtra,
      resultsBody: _results(state),
      applyEnabled: !applyBlocked && (_layouts?.rightIsAutoRig ?? true),
      applyBlockedReason: applyValidation.hasHardLayoutConflicts
          ? 'Fix overlaps or blocked doorways before applying.'
          : (noOp ? 'Auto-Rig matches Baseline — nothing to apply.' : null),
      onApply: applyImproved,
      onRefresh: _rebuild,
      compareLayouts: _layouts,
      onTryAlternate: () => state.cycleBenchAlternate(),
      desktopControls: _desktopControls(state),
      desktopViewport: _desktopViewport(state),
      desktopInspect: _desktopInspect(
        state,
        resultsExtra: resultsExtra,
        onApply: applyBlocked ? null : applyImproved,
        applyBlockedReason: applyValidation.hasHardLayoutConflicts
            ? 'Fix overlaps or blocked doorways before applying.'
            : (noOp ? 'Auto-Rig matches Baseline — nothing to apply.' : null),
      ),
    );
  }

  Widget _desktopControls(AppState state) {
    switch (_step) {
      case _ErgoStep.layout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ERGONOMICS LAYOUT',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchVariantChips(
              selected: _layoutVariant,
              onChanged: _setLayoutVariant,
              ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _roomView == _View.twoD,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _roomView = _View.twoD),
                ),
                BenchChip(
                  label: '3D',
                  selected: _roomView == _View.threeD,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _roomView = _View.threeD),
                ),
                BenchChip(
                  label: 'Compare',
                  selected: _roomView == _View.compare,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _roomView = _View.compare),
                ),
              ],
            ),
            BenchAutoRigMixBar(
              layouts: _layouts,
              onTryAlternate: () {
                context.read<AppState>().cycleBenchAlternate();
                setState(() {
                  _layoutVariant = BenchLayoutKind.improved;
                  _roomView = _View.compare;
                });
              },
            ),
          ],
        );
      case _ErgoStep.simulate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WALK PATHS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _simViz == ErgonomicsVizMode.topDown2D,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _simViz = ErgonomicsVizMode.topDown2D),
                ),
                BenchChip(
                  label: '3D',
                  selected: _simViz == ErgonomicsVizMode.orbit3D,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _simViz = ErgonomicsVizMode.orbit3D),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BenchLayerToggles(
              showPaths: _showPaths,
              onPaths: (v) => setState(() => _showPaths = v),
            ),
            const SizedBox(height: 8),
            const BenchLegend(caption: 'Walk paths'),
          ],
        );
      case _ErgoStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESULTS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Baseline vs Auto-Rig under your Rig Auto-Rig mix.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            BenchVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _simViz == ErgonomicsVizMode.topDown2D,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _simViz = ErgonomicsVizMode.topDown2D),
                ),
                BenchChip(
                  label: '3D',
                  selected: _simViz == ErgonomicsVizMode.orbit3D,
                  color: AppColors.ergonomicsColor,
                  onTap: () => setState(() => _simViz = ErgonomicsVizMode.orbit3D),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _desktopViewport(AppState state) {
    if (_step == _ErgoStep.layout) {
      return _layoutViewportCanvas(state);
    }
    return _simViewportCanvas(state);
  }

  Widget _desktopInspect(
    AppState state, {
    required Widget resultsExtra,
    required VoidCallback? onApply,
    required String? applyBlockedReason,
  }) {
    switch (_step) {
      case _ErgoStep.layout:
        final notes = _notesFor(_layoutVariant);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BenchInspectLockBlock(furniture: _furnitureFor(BenchLayoutKind.myRoom)),
            Text(
              _roomView == _View.compare
                  ? 'Baseline vs Auto-Rig'
                  : switch (_layoutVariant) {
                      BenchLayoutKind.myRoom =>
                        (_layouts?.fellBackToSample ?? false)
                            ? 'Reference sample — no baseline inventory'
                            : 'Baseline — ${_furnitureFor(BenchLayoutKind.myRoom).length} pinned items',
                    BenchLayoutKind.improved =>
                        _layouts?.improvedCaption ?? 'Auto-Rig',
                      BenchLayoutKind.sample =>
                        'Sample room — chair blocked, gear out of reach',
                    },
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ...notes.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (_layoutVariant) {
                        BenchLayoutKind.improved => Icons.check_circle_outline,
                        BenchLayoutKind.myRoom => Icons.chair_alt_outlined,
                        BenchLayoutKind.sample => Icons.warning_amber_rounded,
                      },
                      size: 14,
                      color: switch (_layoutVariant) {
                        BenchLayoutKind.improved => AppColors.green,
                        BenchLayoutKind.myRoom => AppColors.cyan,
                        BenchLayoutKind.sample => AppColors.amber,
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedFurnitureId != null) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final furniture = _layoutFurnitureFor(state);
                  FurnitureItem? item;
                  for (final f in furniture) {
                    if (f.id == _selectedFurnitureId) {
                      item = f;
                      break;
                    }
                  }
                  if (item == null) return const SizedBox.shrink();
                  final color = categoryColor(item.category);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.touch_app_rounded, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.name.toUpperCase()} · ${item.category}',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                benchInspectBlurb(item, mode: 'ergonomics'),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        );
      case _ErgoStep.simulate:
        final m = _activeSim?.metrics;
        if (m == null) return const SizedBox.shrink();
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: BenchMetricTile(
                    label: 'Comfort',
                    value: m.comfortScore,
                    color: AppColors.ergonomicsColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BenchMetricTile(
                    label: 'Walks',
                    value: m.pathScore * 100,
                    color: AppColors.cyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BenchMetricTile(
              label: 'Bed privacy',
              value: m.bedPrivacy * 100,
              color: AppColors.amber,
            ),
          ],
        );
      case _ErgoStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resultsExtra,
            const SizedBox(height: 12),
            _results(state),
            const SizedBox(height: 16),
            BenchApplyRow(
              onApply: onApply,
              onRefresh: _rebuild,
              blockedReason: applyBlockedReason,
            ),
          ],
        );
    }
  }

  Widget _layoutViewportCanvas(AppState state) {
    final room = state.currentRoomData;
    final furniture = _layoutFurnitureFor(state);
    if (_roomView == _View.compare) {
      return BenchSideBySidePlans(
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        myRoom: _furnitureFor(BenchLayoutKind.myRoom),
        improved: _furnitureFor(BenchLayoutKind.improved),
        accentColor: AppColors.ergonomicsColor,
      );
    }
    return ColoredBox(
      color: AppColors.surface,
      child: _roomView == _View.twoD
          ? LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final hit = BenchRoom2DGeometry.hitTest(
                      local: details.localPosition,
                      size: size,
                      gridCols: room.gridCols,
                      gridRows: room.gridRows,
                      furniture: furniture,
                    );
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (hit == null || _selectedFurnitureId == hit.id) {
                        _selectedFurnitureId = null;
                      } else {
                        _selectedFurnitureId = hit.id;
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: BenchRoom2DPainter(
                      gridCols: room.gridCols,
                      gridRows: room.gridRows,
                      furniture: furniture,
                      selectedId: _selectedFurnitureId,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            )
          : _orbit(
              key: const ValueKey('ergo_layout_orbit_desk'),
              resetNonce: _layoutOrbitResetNonce,
              onDoubleTap: () {
                HapticFeedback.lightImpact();
                setState(() => _layoutOrbitResetNonce++);
              },
              lookAtX: room.gridCols * 0.5,
              lookAtZ: room.gridRows * 0.5,
              roomWidth: room.gridCols.toDouble(),
              roomDepth: room.gridRows.toDouble(),
              roomHeight: room.heightMeters,
              builder: (cam) => CustomPaint(
                painter: BenchRoom3DPainter(
                  roomWidth: room.gridCols.toDouble(),
                  roomDepth: room.gridRows.toDouble(),
                  roomHeight: room.heightMeters,
                  gridCols: room.gridCols,
                  gridRows: room.gridRows,
                  yaw: cam.yaw,
                  pitch: cam.pitch,
                  distance: cam.distance,
                  lookAtX: cam.lookAtX,
                  lookAtZ: cam.lookAtZ,
                  furniture: furniture,
                ),
                child: const SizedBox.expand(),
              ),
            ),
    );
  }

  Widget _simViewportCanvas(AppState state) {
    final sim = _activeSim;
    if (sim == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ergonomicsColor));
    }
    return _simViz == ErgonomicsVizMode.topDown2D
        ? AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => CustomPaint(
              painter: ErgonomicsFieldPainter(
                snapshot: sim,
                vizMode: _simViz,
                yaw: _defaultYaw,
                pitch: _defaultPitch,
                distance: _defaultDistance,
                pulse: _pulse.value,
                showPaths: _showPaths,
              ),
              child: const SizedBox.expand(),
            ),
          )
        : _orbit(
            key: const ValueKey('ergo_sim_orbit_desk'),
            resetNonce: _simOrbitResetNonce,
            onDoubleTap: () {
              HapticFeedback.lightImpact();
              setState(() => _simOrbitResetNonce++);
            },
            lookAtX: sim.roomWidth * 0.5,
            lookAtZ: sim.roomDepth * 0.5,
            roomWidth: sim.roomWidth,
            roomDepth: sim.roomDepth,
            roomHeight: sim.roomHeight,
            builder: (cam) => AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => CustomPaint(
                painter: ErgonomicsFieldPainter(
                  snapshot: sim,
                  vizMode: _simViz,
                  yaw: cam.yaw,
                  pitch: cam.pitch,
                  distance: cam.distance,
                  lookAtX: cam.lookAtX,
                  lookAtZ: cam.lookAtZ,
                  pulse: _pulse.value,
                  showPaths: _showPaths,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
  }

  Widget _layoutSection(AppState state) {
    final notes = _notesFor(_layoutVariant);
    final room = state.currentRoomData;
    final furniture = _layoutFurnitureFor(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ERGONOMICS LAYOUT',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        BenchVariantChips(
          selected: _layoutVariant,
          onChanged: _setLayoutVariant,
          ),
        BenchViewChips(
          children: [
            BenchChip(
              label: '2D',
              selected: _roomView == _View.twoD,
              color: AppColors.ergonomicsColor,
              onTap: () => setState(() => _roomView = _View.twoD),
            ),
            BenchChip(
              label: '3D',
              selected: _roomView == _View.threeD,
              color: AppColors.ergonomicsColor,
              onTap: () => setState(() => _roomView = _View.threeD),
            ),
            BenchChip(
              label: 'Compare',
              selected: _roomView == _View.compare,
              color: AppColors.ergonomicsColor,
              onTap: () => setState(() => _roomView = _View.compare),
            ),
          ],
        ),
        BenchAutoRigMixBar(
          layouts: _layouts,
          onTryAlternate: () {
            context.read<AppState>().cycleBenchAlternate();
            setState(() {
              _layoutVariant = BenchLayoutKind.improved;
              _roomView = _View.compare;
            });
          },
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _roomView == _View.compare
                    ? 'Baseline vs Auto-Rig — same Auto-Rig mix as Rig'
                    : switch (_layoutVariant) {
                        BenchLayoutKind.myRoom =>
                          (_layouts?.fellBackToSample ?? false)
                              ? 'Reference room — no baseline inventory'
                              : 'Baseline — ${_furnitureFor(BenchLayoutKind.myRoom).length} pinned items',
                        BenchLayoutKind.improved =>
                          _layouts?.improvedCaption ??
                              'Auto-Rig · from Baseline',
                        BenchLayoutKind.sample =>
                          'Sample room — chair blocked, gear out of reach',
                      },
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (_roomView == _View.compare)
                BenchSideBySidePlans(
                  gridCols: room.gridCols,
                  gridRows: room.gridRows,
                  myRoom: _furnitureFor(BenchLayoutKind.myRoom),
                  improved: _furnitureFor(BenchLayoutKind.improved),
                  accentColor: AppColors.ergonomicsColor,
                )
              else
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(
                            '${_layoutVariant.name}_${_roomView.name}_${_layouts?.fingerprint ?? ''}_${_layouts?.requestedAlternateIndex ?? 0}',
                          ),
                          child: _roomView == _View.twoD
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    final size = Size(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    );
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (details) {
                                        final hit = BenchRoom2DGeometry.hitTest(
                                          local: details.localPosition,
                                          size: size,
                                          gridCols: room.gridCols,
                                          gridRows: room.gridRows,
                                          furniture: furniture,
                                        );
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          if (hit == null ||
                                              _selectedFurnitureId == hit.id) {
                                            _selectedFurnitureId = null;
                                          } else {
                                            _selectedFurnitureId = hit.id;
                                          }
                                        });
                                      },
                                      child: CustomPaint(
                                        painter: BenchRoom2DPainter(
                                          gridCols: room.gridCols,
                                          gridRows: room.gridRows,
                                          furniture: furniture,
                                          selectedId: _selectedFurnitureId,
                                        ),
                                        child: const SizedBox.expand(),
                                      ),
                                    );
                                  },
                                )
                              : _orbit(
                                  key: const ValueKey('ergo_layout_orbit'),
                                  resetNonce: _layoutOrbitResetNonce,
                                  onDoubleTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() => _layoutOrbitResetNonce++);
                                  },
                                  lookAtX: room.gridCols * 0.5,
                                  lookAtZ: room.gridRows * 0.5,
                                  roomWidth: room.gridCols.toDouble(),
                                  roomDepth: room.gridRows.toDouble(),
                                  roomHeight: room.heightMeters,
                                  builder: (cam) => CustomPaint(
                                    painter: BenchRoom3DPainter(
                                      roomWidth: room.gridCols.toDouble(),
                                      roomDepth: room.gridRows.toDouble(),
                                      roomHeight: room.heightMeters,                                      gridCols: room.gridCols,
                                      gridRows: room.gridRows,
                                      yaw: cam.yaw,
                                      pitch: cam.pitch,
                                      distance: cam.distance,
                                      lookAtX: cam.lookAtX,
                                      lookAtZ: cam.lookAtZ,
                                      furniture: furniture,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selectedFurnitureId != null) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    FurnitureItem? item;
                    for (final f in furniture) {
                      if (f.id == _selectedFurnitureId) {
                        item = f;
                        break;
                      }
                    }
                    if (item == null) return const SizedBox.shrink();
                    final color = categoryColor(item.category);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.touch_app_rounded, size: 16, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.name.toUpperCase()} · ${item.category}',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  benchInspectBlurb(item, mode: 'ergonomics'),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              ...notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (_layoutVariant) {
                          BenchLayoutKind.improved => Icons.check_circle_outline,
                          BenchLayoutKind.myRoom => Icons.chair_alt_outlined,
                          BenchLayoutKind.sample => Icons.warning_amber_rounded,
                        },
                        size: 14,
                        color: switch (_layoutVariant) {
                          BenchLayoutKind.improved => AppColors.green,
                          BenchLayoutKind.myRoom => AppColors.cyan,
                          BenchLayoutKind.sample => AppColors.amber,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(n, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _simSection(AppState state) {
    _syncFromState(state);
    final sim = _activeSim;
    if (sim == null) return const SizedBox.shrink();
    final m = sim.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WALK PATHS',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        BenchVariantChips(
          selected: _simVariant,
          onChanged: (v) => setState(() => _simVariant = v),
        ),
        BenchViewChips(
          children: [
            BenchChip(
              label: '2D',
              selected: _simViz == ErgonomicsVizMode.topDown2D,
              color: AppColors.ergonomicsColor,
              onTap: () => setState(() => _simViz = ErgonomicsVizMode.topDown2D),
            ),
            BenchChip(
              label: '3D',
              selected: _simViz == ErgonomicsVizMode.orbit3D,
              color: AppColors.ergonomicsColor,
              onTap: () => setState(() => _simViz = ErgonomicsVizMode.orbit3D),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BenchLayerToggles(
          showPaths: _showPaths,
          onPaths: (v) => setState(() => _showPaths = v),
        ),
        const SizedBox(height: 8),
        const BenchLegend(caption: 'Walk paths'),
        const SizedBox(height: 12),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: _simViz == ErgonomicsVizMode.topDown2D
              ? AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => CustomPaint(
                    painter: ErgonomicsFieldPainter(
                      snapshot: sim,
                      vizMode: _simViz,
                      yaw: _defaultYaw,
                      pitch: _defaultPitch,
                      distance: _defaultDistance,
                      pulse: _pulse.value,
                      showPaths: _showPaths,
                    ),
                    child: const SizedBox.expand(),
                  ),
                )
              : _orbit(
                  key: const ValueKey('ergo_sim_orbit'),
                  resetNonce: _simOrbitResetNonce,
                  onDoubleTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _simOrbitResetNonce++);
                  },
                  lookAtX: sim.roomWidth * 0.5,
                  lookAtZ: sim.roomDepth * 0.5,
                  roomWidth: sim.roomWidth,
                  roomDepth: sim.roomDepth,
                  roomHeight: sim.roomHeight,
                  builder: (cam) => AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => CustomPaint(
                      painter: ErgonomicsFieldPainter(
                        snapshot: sim,
                        vizMode: _simViz,
                        yaw: cam.yaw,
                        pitch: cam.pitch,
                        distance: cam.distance,
                        lookAtX: cam.lookAtX,
                        lookAtZ: cam.lookAtZ,
                        pulse: _pulse.value,
                        showPaths: _showPaths,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: BenchMetricTile(label: 'Comfort', value: m.comfortScore, color: AppColors.ergonomicsColor)),
            const SizedBox(width: 8),
            Expanded(child: BenchMetricTile(label: 'Walks', value: m.pathScore * 100, color: AppColors.cyan)),
            const SizedBox(width: 8),
            Expanded(child: BenchMetricTile(label: 'Bed privacy', value: m.bedPrivacy * 100, color: AppColors.amber)),
          ],
        ),
      ],
    );
  }

  /// Validate the layout the results header is actually showing, so the badge,
  /// the score rings, and the check rows all describe the same furniture.
  BenchmarkValidation _validationForSimVariant(AppState state) {
    final kind = _step == _ErgoStep.results ? BenchLayoutKind.improved : _simVariant;
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(kind),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'ergonomics',
    );
  }

  Widget _results(AppState state) {
    final validation = _validationForSimVariant(state);
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final pathDelta = ((opt.pathScore - base.pathScore) * 100).round();
    final pathLabel = pathDelta >= 0 ? '+$pathDelta' : '$pathDelta';
    return BenchResultsCard(
      title: 'Ergonomics Comfort Bench',
      accentColor: AppColors.ergonomicsColor,
      validation: validation,
      whyReasons: _layouts?.improvedReasons ?? const [],
      rings: [
        BenchScoreRingSpec(score: base.comfortScore, color: AppColors.cyan, label: 'Baseline'),
        BenchScoreRingSpec(score: opt.comfortScore, color: AppColors.ergonomicsColor, label: 'Auto-Rig'),
      ],
      summaryText:
          'Walk paths $pathLabel · '
          'Door view +${((opt.doorProspect - base.doorProspect) * 100).toStringAsFixed(0)} · '
          'Window +${((opt.windowSideLight - base.windowSideLight) * 100).toStringAsFixed(0)} · '
          'HVAC +${((opt.hvacClearance - base.hvacClearance) * 100).toStringAsFixed(0)}',
    );
  }

  Widget _orbit({
    Key? key,
    required Widget Function(BenchOrbitCamera cam) builder,
    required int resetNonce,
    VoidCallback? onDoubleTap,
    double lookAtX = 3,
    double lookAtZ = 4,
    double roomWidth = 6,
    double roomDepth = 8,
    double roomHeight = RoomScale.defaultHeightMeters,
  }) {
    return BenchOrbitShell(
      key: key,
      initialYaw: _defaultYaw,
      initialPitch: _defaultPitch,
      initialDistance: _defaultDistance,
      initialLookAtX: lookAtX,
      initialLookAtZ: lookAtZ,
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      resetNonce: resetNonce,
      onDoubleTap: onDoubleTap,
      onDragChanged: (dragging) {
        if (_orbitDragging != dragging) {
          setState(() => _orbitDragging = dragging);
          widget.onOrbitDraggingChanged?.call(dragging);
        }
      },
      builder: builder,
    );
  }

}
