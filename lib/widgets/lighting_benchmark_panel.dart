// lib/widgets/lighting_benchmark_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/sim_room_bounds.dart';
import '../services/benchmark_layouts.dart';
import '../services/layout_share_image.dart';
import '../services/lighting_simulator.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'benchmark_panel_scaffold.dart';
import 'benchmark_room_views.dart';
import 'glass_card.dart';
import 'lighting_field_painter.dart';
import 'room_icons.dart';

enum _LightStep { layout, simulate, results }
enum _View { twoD, threeD, compare }

class LightingBenchmarkPanel extends StatefulWidget {
  final ValueChanged<bool>? onOrbitDraggingChanged;

  const LightingBenchmarkPanel({super.key, this.onOrbitDraggingChanged});

  @override
  State<LightingBenchmarkPanel> createState() => _LightingBenchmarkPanelState();
}

class _LightingBenchmarkPanelState extends State<LightingBenchmarkPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  _LightStep _step = _LightStep.layout;
  BenchmarkLayoutKind _layoutVariant = BenchmarkLayoutKind.currentRoom;
  BenchmarkLayoutKind _simVariant = BenchmarkLayoutKind.currentRoom;
  _View _roomView = _View.twoD;
  LightingVizMode _simViz = LightingVizMode.topDown2D;

  bool _orbitDragging = false;
  int _layoutOrbitResetNonce = 0;
  int _simOrbitResetNonce = 0;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.7;
  static const _defaultPitch = 0.4;
  static const _defaultDistance = 16.0;

  bool _showResults = false;
  bool _ready = false;

  BenchmarkLayouts? _layouts;
  String? _layoutSyncKey;
  int _seenFocusToken = 0;
  int _seenResultsFocusToken = 0;
  LightingSimSnapshot? _myRoomSim;
  LightingSimSnapshot? _improvedSim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The benchmark reads the Room; opening this tab must never write to it.
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

  /// Rebuilds the lighting fields from the furniture that is in the Room.
  /// Safe to call during build: it only touches fields.
  void _recompute(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final left =
        state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft) ?? const [];
    final rightIsAuto = state.benchmarkCompareRight.isAutoRig;
    final right = rightIsAuto
        ? null
        : state.resolveBenchmarkCompareFurniture(state.benchmarkCompareRight);
    final layouts = BenchmarkLayoutBuilder.build(
      mode: BenchmarkMode.lighting,
      roomFurniture: state.committedFurniture,
      leftFurniture: left,
      rightFurniture: right,
      rightIsAutoRig: rightIsAuto,
      autoRigSeed: state.benchmarkAutoRigSeedFurniture(forRight: true),
      leftCaption: state.benchmarkCompareSourceLabel(state.benchmarkCompareLeft),
      rightCaption: state.benchmarkCompareSourceLabel(state.benchmarkCompareRight),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: state.optimizeWeights,
      alternateIndex: state.benchmarkAlternateCursor,
    );
    _layouts = layouts;
    final bounds = SimRoomBounds.fromRoomData(room);
    _myRoomSim = LightingSimulator.build(furniture: layouts.currentRoom, optimized: false, bounds: bounds);
    _improvedSim = LightingSimulator.build(furniture: layouts.autoRig, optimized: true, bounds: bounds);
    _ready = true;
    if (resetStep) {
      _step = _LightStep.layout;
      // A pending focus request (the Room's "Sim Prototype" button) wins once;
      // after that a reset lands back on the user's own room.
      final pending = state.benchmarkLayoutFocusToken != _seenFocusToken;
      var kind = pending ? state.benchmarkLayoutFocus : BenchmarkLayoutKind.currentRoom;
      _seenFocusToken = state.benchmarkLayoutFocusToken;
      _layoutVariant = kind;
      _simVariant = kind;
      _showResults = false;
    }
  }

  /// Picks up Room edits so the light field always describes the current room.
  /// Called from build, so it must not call setState.
  void _syncFromState(AppState state) {
    _syncPulseForTab(state);
    if (state.currentTab != benchmarkTabIndex) return;
    if (state.benchmarkLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchmarkLayoutFocusToken;
      var kind = state.benchmarkLayoutFocus;
      _layoutVariant = kind;
      _simVariant = kind;
      _selectedFurnitureId = null;
    }
    if (state.benchmarkResultsFocusToken != _seenResultsFocusToken) {
      _seenResultsFocusToken = state.benchmarkResultsFocusToken;
      _showResults = true;
      _step = _LightStep.results;
      _simVariant = BenchmarkLayoutKind.autoRig;
      _layoutVariant = BenchmarkLayoutKind.autoRig;
    }
    final key =
        '${benchmarkCompareFingerprint(state)}|${state.optimizeWeights.cacheKey}|${state.benchmarkAlternateCursor}';
    if (_layouts != null && _layoutSyncKey == key) return;
    _layoutSyncKey = key;
    _recompute(state, resetStep: false);
  }

  void _syncPulseForTab(AppState state) {
    final onBenchmark = state.currentTab == benchmarkTabIndex;
    if (onBenchmark) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  List<FurnitureItem> _furnitureFor(BenchmarkLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  List<FurnitureItem> _layoutFurnitureFor(AppState state) => _furnitureFor(_layoutVariant);

  int get _stepIndex => switch (_step) {
        _LightStep.layout => benchmarkStepLayout,
        _LightStep.simulate => benchmarkStepMiddle,
        _LightStep.results => benchmarkStepResults,
      };

  _LightStep _stepFromIndex(int i) => switch (i) {
        benchmarkStepLayout => _LightStep.layout,
        benchmarkStepMiddle => _LightStep.simulate,
        _ => _LightStep.results,
      };

  String get _layoutHint => _layouts?.isEmpty ?? false
      ? 'No room to score — create or stock a room first, then return to Benchmark.'
      : 'Scores Baseline vs Auto-Rig (same engine as Room Tools → Auto-Rig). Apply writes Auto-Rig onto your Room.';

  LightingSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case BenchmarkLayoutKind.autoRig:
        return _improvedSim;
      case BenchmarkLayoutKind.currentRoom:
              return _myRoomSim;
    }
  }

  List<String> _notesFor(BenchmarkLayoutKind kind) {
    switch (kind) {
      case BenchmarkLayoutKind.currentRoom:
        if (_layouts?.isEmpty ?? false) {
          return const [
            'No furniture yet — create a room before Benchmark can score',
            'Add furniture on Room, then Set baseline (Compare)',
          ];
        }
        return const [
          'Pinned Baseline inventory for this lot',
          'Room edits do not move Baseline until you Set baseline again',
        ];
      case BenchmarkLayoutKind.autoRig:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that lights Baseline better']
            : reasons;
    }
  }

  void _runBenchmark() {
    // Sims are sync — open Results on Improved immediately.
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _showResults = true;
      _step = _LightStep.results;
      _simVariant = BenchmarkLayoutKind.autoRig;
      _layoutVariant = BenchmarkLayoutKind.autoRig;
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
        child: Center(child: CircularProgressIndicator(color: AppColors.lightingColor)),
      );
    }

    final applyValidation = _validationForSimVariant(state);
    final noOp = improvedLayoutIsNoOp(_layouts);
    final applyBlocked = noOp || applyValidation.hasHardLayoutConflicts;

    Future<void> applyImproved() async {
      if (!await confirmBenchmarkApply(
        context,
        validation: applyValidation,
        isEmpty: _layouts?.isEmpty ?? false,
      )) {
        return;
      }
      if (!context.mounted) return;
      final before = List<FurnitureItem>.from(state.committedFurniture);
      state.applyFurnitureLayout(
        _furnitureFor(BenchmarkLayoutKind.autoRig),
        markOptimized: true,
        lockMode: 'lighting',
      );
      final diff = summarizeLayoutDiff(before, state.furniture);
      final why = summarizeWhyWins(_layouts?.improvedReasons ?? const []);
      final room = state.currentRoomData;
      final after = List<FurnitureItem>.from(state.furniture);
      showBenchmarkApplySnackBar(
        context,
        message: why.isEmpty ? 'Lighting applied · $diff' : 'Lighting applied · $diff · $why',
        accentColor: AppColors.lightingColor,
        onOpenRoom: () => state.setTab(roomTabIndex),
        onKeepAsBaseline: () => state.keepAppliedAsBenchmarkBaseline(),
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
        ? benchmarkImprovedNoOpBanner(
            message:
                'Auto-Rig matches Baseline — lighting is already as good as the optimizer found.',
          )
        : benchmarkWhyWinsCard(
            reasons: _layouts?.improvedReasons ?? const [],
            accentColor: AppColors.lightingColor,
          );

    return BenchmarkPanelScaffold(
      accentColor: AppColors.lightingColor,
      step: _stepIndex,
      stepLabels: kBenchmarkStepLabels,
      resultsEnabled: _showResults,
      running: false,
      onStepChanged: (i) => setState(() => _step = _stepFromIndex(i)),
      layoutBody: _layoutSection(state),
      layoutRunAction: BenchmarkRunAction(
        buttonLabel: 'RUN LIGHTING BENCHMARK',
        icon: RoomSvg.scan,
        onRun: _runBenchmark,
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
      onTryAlternate: () => state.cycleBenchmarkAlternate(),
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
      case _LightStep.layout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LIGHTING LAYOUT',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchmarkVariantChips(
              selected: _layoutVariant,
              onChanged: _setLayoutVariant,
              ),
            BenchmarkViewChips(
              children: [
                BenchmarkChip(
                  label: '2D',
                  selected: _roomView == _View.twoD,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _roomView = _View.twoD),
                ),
                BenchmarkChip(
                  label: '3D',
                  selected: _roomView == _View.threeD,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _roomView = _View.threeD),
                ),
                BenchmarkChip(
                  label: 'Compare',
                  selected: _roomView == _View.compare,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _roomView = _View.compare),
                ),
              ],
            ),
            BenchmarkAutoRigMixBar(
              layouts: _layouts,
              onTryAlternate: () {
                context.read<AppState>().cycleBenchmarkAlternate();
                setState(() {
                  _layoutVariant = BenchmarkLayoutKind.autoRig;
                  _roomView = _View.compare;
                });
              },
            ),
          ],
        );
      case _LightStep.simulate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ILLUMINANCE FIELD',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchmarkVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchmarkViewChips(
              children: [
                BenchmarkChip(
                  label: '2D',
                  selected: _simViz == LightingVizMode.topDown2D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
                ),
                BenchmarkChip(
                  label: '3D',
                  selected: _simViz == LightingVizMode.orbit3D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.orbit3D),
                ),
              ],
            ),
          ],
        );
      case _LightStep.results:
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
              'Baseline vs Auto-Rig under your Room Auto-Rig mix.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            BenchmarkVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchmarkViewChips(
              children: [
                BenchmarkChip(
                  label: '2D',
                  selected: _simViz == LightingVizMode.topDown2D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
                ),
                BenchmarkChip(
                  label: '3D',
                  selected: _simViz == LightingVizMode.orbit3D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.orbit3D),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _desktopViewport(AppState state) {
    if (_step == _LightStep.layout) {
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
      case _LightStep.layout:
        final notes = _notesFor(_layoutVariant);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BenchmarkInspectLockBlock(furniture: _furnitureFor(BenchmarkLayoutKind.currentRoom)),
            Text(
              _roomView == _View.compare
                  ? 'Baseline vs Auto-Rig'
                  : switch (_layoutVariant) {
                      BenchmarkLayoutKind.currentRoom =>
                        (_layouts?.isEmpty ?? false)
                            ? 'Empty room — add furniture before scoring'
                            : 'Baseline — ${_furnitureFor(BenchmarkLayoutKind.currentRoom).length} pinned items',
                    BenchmarkLayoutKind.autoRig =>
                        _layouts?.improvedCaption ?? 'Auto-Rig',
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
                      _layoutVariant == BenchmarkLayoutKind.currentRoom
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 14,
                      color: switch (_layoutVariant) {
                        BenchmarkLayoutKind.currentRoom => AppColors.cyan,
                        BenchmarkLayoutKind.autoRig => AppColors.green,
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
          ],
        );
      case _LightStep.simulate:
        final m = _activeSim?.metrics;
        if (m == null) return const SizedBox.shrink();
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: BenchmarkMetricTile(
                    label: 'Exposure',
                    value: m.exposureScore,
                    color: AppColors.lightingColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BenchmarkMetricTile(
                    label: 'Task light',
                    value: m.taskIllumination * 100,
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BenchmarkMetricTile(
              label: 'Shadows',
              value: m.shadowRatio * 100,
              color: AppColors.red,
              invert: true,
            ),
          ],
        );
      case _LightStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resultsExtra,
            const SizedBox(height: 12),
            _results(state),
            const SizedBox(height: 16),
            BenchmarkApplyRow(
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
      return BenchmarkSideBySidePlans(
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        currentRoom: _furnitureFor(BenchmarkLayoutKind.currentRoom),
        autoRig: _furnitureFor(BenchmarkLayoutKind.autoRig),
        accentColor: AppColors.lightingColor,
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
                    final hit = BenchmarkRoom2DGeometry.hitTest(
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
                    painter: BenchmarkRoom2DPainter(
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
              key: const ValueKey('lighting_layout_orbit_desk'),
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
                painter: BenchmarkRoom3DPainter(
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
      return const Center(child: CircularProgressIndicator(color: AppColors.lightingColor));
    }
    return _simViz == LightingVizMode.topDown2D
        ? AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => CustomPaint(
              painter: LightingFieldPainter(
                snapshot: sim,
                furniture: _furnitureFor(_simVariant),
                vizMode: _simViz,
                yaw: _defaultYaw,
                pitch: _defaultPitch,
                distance: _defaultDistance,
                pulse: _pulse.value,
              ),
              child: const SizedBox.expand(),
            ),
          )
        : _orbit(
            key: const ValueKey('lighting_sim_orbit_desk'),
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
                painter: LightingFieldPainter(
                  snapshot: sim,
                  furniture: _furnitureFor(_simVariant),
                  vizMode: _simViz,
                  yaw: cam.yaw,
                  pitch: cam.pitch,
                  distance: cam.distance,
                  lookAtX: cam.lookAtX,
                  lookAtZ: cam.lookAtZ,
                  pulse: _pulse.value,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
  }

  /// Switching layouts only changes what is displayed — it never writes to the
  /// Room. Pushing a layout back is the explicit Apply action under the results.
  void _setLayoutVariant(BenchmarkLayoutKind next) {
    if (_layoutVariant == next) return;
    HapticFeedback.selectionClick();
    setState(() {
      _layoutVariant = next;
      _selectedFurnitureId = null;
    });
  }

  Widget _layoutSection(AppState state) {
    final notes = _notesFor(_layoutVariant);
    final room = state.currentRoomData;
    final furniture = _layoutFurnitureFor(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIGHTING LAYOUT',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        BenchmarkVariantChips(
          selected: _layoutVariant,
          onChanged: _setLayoutVariant,
          ),
        BenchmarkViewChips(
          children: [
            BenchmarkChip(
              label: '2D',
              selected: _roomView == _View.twoD,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _roomView = _View.twoD),
            ),
            BenchmarkChip(
              label: '3D',
              selected: _roomView == _View.threeD,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _roomView = _View.threeD),
            ),
            BenchmarkChip(
              label: 'Compare',
              selected: _roomView == _View.compare,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _roomView = _View.compare),
            ),
          ],
        ),
        BenchmarkAutoRigMixBar(
          layouts: _layouts,
          onTryAlternate: () {
            context.read<AppState>().cycleBenchmarkAlternate();
            setState(() {
              _layoutVariant = BenchmarkLayoutKind.autoRig;
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
                    ? 'Baseline vs Auto-Rig — same Auto-Rig mix as Room'
                    : switch (_layoutVariant) {
                        BenchmarkLayoutKind.currentRoom =>
                          (_layouts?.isEmpty ?? false)
                              ? 'Empty room — add furniture before scoring'
                              : 'Baseline — ${_furnitureFor(BenchmarkLayoutKind.currentRoom).length} pinned items',
                        BenchmarkLayoutKind.autoRig =>
                          _layouts?.improvedCaption ??
                              'Auto-Rig · from Baseline',
                      },
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (_roomView == _View.compare)
                BenchmarkSideBySidePlans(
                  gridCols: room.gridCols,
                  gridRows: room.gridRows,
                  currentRoom: _furnitureFor(BenchmarkLayoutKind.currentRoom),
                  autoRig: _furnitureFor(BenchmarkLayoutKind.autoRig),
                  accentColor: AppColors.lightingColor,
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
                                        final hit = BenchmarkRoom2DGeometry.hitTest(
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
                                        painter: BenchmarkRoom2DPainter(
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
                                  key: const ValueKey('lighting_layout_orbit'),
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
                                    painter: BenchmarkRoom3DPainter(
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
                                  benchmarkInspectBlurb(item, mode: 'lighting'),
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
                        _layoutVariant == BenchmarkLayoutKind.currentRoom
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 14,
                        color: switch (_layoutVariant) {
                          BenchmarkLayoutKind.currentRoom => AppColors.cyan,
                          BenchmarkLayoutKind.autoRig => AppColors.green,
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
          'ILLUMINANCE FIELD',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        BenchmarkVariantChips(
          selected: _simVariant,
          onChanged: (v) => setState(() => _simVariant = v),
        ),
        BenchmarkViewChips(
          children: [
            BenchmarkChip(
              label: '2D',
              selected: _simViz == LightingVizMode.topDown2D,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
            ),
            BenchmarkChip(
              label: '3D',
              selected: _simViz == LightingVizMode.orbit3D,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _simViz = LightingVizMode.orbit3D),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 12),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: _simViz == LightingVizMode.topDown2D
              ? AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => CustomPaint(
                    painter: LightingFieldPainter(
                      snapshot: sim,
                      furniture: _furnitureFor(_simVariant),
                      vizMode: _simViz,
                      yaw: _defaultYaw,
                      pitch: _defaultPitch,
                      distance: _defaultDistance,
                      pulse: _pulse.value,
                    ),
                    child: const SizedBox.expand(),
                  ),
                )
              : _orbit(
                  key: const ValueKey('lighting_sim_orbit'),
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
                      painter: LightingFieldPainter(
                        snapshot: sim,
                        furniture: _furnitureFor(_simVariant),
                        vizMode: _simViz,
                        yaw: cam.yaw,
                        pitch: cam.pitch,
                        distance: cam.distance,
                        lookAtX: cam.lookAtX,
                        lookAtZ: cam.lookAtZ,
                        pulse: _pulse.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: BenchmarkMetricTile(label: 'Exposure', value: m.exposureScore, color: AppColors.lightingColor)),
            const SizedBox(width: 8),
            Expanded(child: BenchmarkMetricTile(label: 'Task light', value: m.taskIllumination * 100, color: AppColors.amber)),
            const SizedBox(width: 8),
            Expanded(child: BenchmarkMetricTile(label: 'Shadows', value: m.shadowRatio * 100, color: AppColors.red, invert: true)),
          ],
        ),
      ],
    );
  }

  /// Validate the layout the results header is actually showing, so the badge,
  /// the score rings, and the check rows all describe the same furniture.
  BenchmarkValidation _validationForSimVariant(AppState state) {
    final kind = _step == _LightStep.results ? BenchmarkLayoutKind.autoRig : _simVariant;
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(kind),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'lighting',
    );
  }

  Widget _results(AppState state) {
    final validation = _validationForSimVariant(state);
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final left = _layouts?.leftCaption ?? 'Left';
    final right = _layouts?.rightCaption ?? 'Right';
    final delta = (opt.exposureScore - base.exposureScore).round();
    final deltaLabel = delta >= 0 ? '+$delta' : '$delta';
    final why = (_layouts?.rightIsAutoRig ?? false)
        ? (_layouts?.improvedReasons ?? const <String>[])
        : const <String>[];
    return BenchmarkResultsCard(
      title: 'Lighting Exposure Benchmark',
      accentColor: AppColors.lightingColor,
      validation: validation,
      compareHeader: 'Now comparing: $left vs $right',
      whyReasons: why,
      rings: [
        BenchmarkScoreRingSpec(
          score: base.exposureScore,
          color: AppColors.cyan,
          label: left,
        ),
        BenchmarkScoreRingSpec(
          score: opt.exposureScore,
          color: AppColors.lightingColor,
          label: right,
        ),
      ],
      summaryText:
          'Exposure $deltaLabel · '
          'Shadows ${((base.shadowRatio - opt.shadowRatio) * 100).toStringAsFixed(0)} pts · '
          'Task light +${((opt.taskIllumination - base.taskIllumination) * 100).toStringAsFixed(0)}',
      metricRows: [
        BenchmarkMetricComparisonRow(
          label: 'Exposure',
          left: base.exposureScore,
          right: opt.exposureScore,
          color: AppColors.lightingColor,
        ),
        BenchmarkMetricComparisonRow(
          label: 'Task light',
          left: base.taskIllumination * 100,
          right: opt.taskIllumination * 100,
          color: AppColors.amber,
        ),
        BenchmarkMetricComparisonRow(
          label: 'Shadows',
          left: base.shadowRatio * 100,
          right: opt.shadowRatio * 100,
          color: AppColors.red,
          lowerIsBetter: true,
        ),
      ],
    );
  }

  Widget _orbit({
    Key? key,
    required Widget Function(BenchmarkOrbitCamera cam) builder,
    required int resetNonce,
    VoidCallback? onDoubleTap,
    double lookAtX = 3,
    double lookAtZ = 4,
    double roomWidth = 6,
    double roomDepth = 8,
    double roomHeight = RoomScale.defaultHeightMeters,
  }) {
    return BenchmarkOrbitShell(
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
