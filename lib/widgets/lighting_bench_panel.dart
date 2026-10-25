// lib/widgets/lighting_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/sim_room_bounds.dart';
import '../services/bench_layouts.dart';
import '../services/layout_share_image.dart';
import '../services/lighting_simulator.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'bench_panel_scaffold.dart';
import 'bench_room_views.dart';
import 'chrome/bench_results_chrome.dart';
import 'glass_card.dart';
import 'lighting_field_painter.dart';
import 'room_icons.dart';

enum _LightStep { layout, simulate, results }
enum _View { twoD, threeD, compare }

class LightingBenchPanel extends StatefulWidget {
  final ValueChanged<bool>? onOrbitDraggingChanged;

  const LightingBenchPanel({super.key, this.onOrbitDraggingChanged});

  @override
  State<LightingBenchPanel> createState() => _LightingBenchPanelState();
}

class _LightingBenchPanelState extends State<LightingBenchPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  _LightStep _step = _LightStep.layout;
  BenchLayoutKind _layoutVariant = BenchLayoutKind.myRoom;
  BenchLayoutKind _simVariant = BenchLayoutKind.myRoom;
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

  BenchLayouts? _layouts;
  int _seenFocusToken = 0;
  LightingSimSnapshot? _myRoomSim;
  LightingSimSnapshot? _improvedSim;

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

  /// Rebuilds the lighting fields from the furniture that is in the Rig.
  /// Safe to call during build: it only touches fields.
  void _recompute(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.lighting,
      roomFurniture: state.committedFurniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: state.optimizeWeights,
      alternateIndex: state.benchAlternateCursor,
    );
    _layouts = layouts;
    final bounds = SimRoomBounds.fromRoomData(room);
    _myRoomSim = LightingSimulator.build(furniture: layouts.myRoom, optimized: false, bounds: bounds);
    _improvedSim = LightingSimulator.build(furniture: layouts.improved, optimized: true, bounds: bounds);
    _ready = true;
    if (resetStep) {
      _step = _LightStep.layout;
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

  /// Picks up Rig edits so the light field always describes the current room.
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
    final fp = BenchLayoutBuilder.fingerprintOf(
      state.committedFurniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (benchLayoutsInSync(
      _layouts,
      furnitureFingerprint: fp,
      weightsCacheKey: state.optimizeWeights.cacheKey,
      alternateCursor: state.benchAlternateCursor,
    )) {
      return;
    }
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
        _LightStep.layout => benchStepLayout,
        _LightStep.simulate => benchStepMiddle,
        _LightStep.results => benchStepResults,
      };

  _LightStep _stepFromIndex(int i) => switch (i) {
        benchStepLayout => _LightStep.layout,
        benchStepMiddle => _LightStep.simulate,
        _ => _LightStep.results,
      };

  String get _layoutHint => _layouts?.fellBackToSample ?? false
      ? 'Your Rig is empty, so this runs on the reference room. Add furniture in Rig to bench your own space.'
      : '2D lux proxy (not radiosity) on your Rig furniture, then compares a rule-based rearrange of the same room.';

  LightingSimSnapshot? get _activeSim {
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
            'Nothing in the Rig yet — showing the reference room',
            'Add furniture on the Rig tab and this bench follows it',
          ];
        }
        return const [
          'Windows, lamps and blockers all come from your Rig',
          'Move something on the Rig tab and the light field rebuilds here',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that lights your room better']
            : reasons;
      case BenchLayoutKind.sample:
        return const [
          'Reference room used to sanity-check the simulator',
          'Dark task zone — daylight blocked, lamp misplaced',
        ];
    }
  }

  void _runBench() {
    // Sims are sync — open Results on Improved immediately.
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _showResults = true;
      _step = _LightStep.results;
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
        child: Center(child: CircularProgressIndicator(color: AppColors.lightingColor)),
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
        lockMode: 'lighting',
      );
      final diff = summarizeLayoutDiff(before, state.furniture);
      final why = summarizeWhyWins(_layouts?.improvedReasons ?? const []);
      final room = state.currentRoomData;
      final after = List<FurnitureItem>.from(state.furniture);
      showBenchApplySnackBar(
        context,
        message: why.isEmpty ? 'Lighting applied · $diff' : 'Lighting applied · $diff · $why',
        accentColor: AppColors.lightingColor,
        onOpenRig: () => state.setTab(2),
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
                'Improved layout matches your room — lighting is already as good as the optimizer found.',
          )
        : benchWhyWinsCard(
            reasons: _layouts?.improvedReasons ?? const [],
            accentColor: AppColors.lightingColor,
          );

    return BenchPanelScaffold(
      accentColor: AppColors.lightingColor,
      step: _stepIndex,
      stepLabels: const ['1. Layout', '2. Light Field', '3. Results'],
      resultsEnabled: _showResults,
      running: false,
      onStepChanged: (i) => setState(() => _step = _stepFromIndex(i)),
      layoutBody: _layoutSection(state),
      layoutRunAction: BenchRunAction(
        buttonLabel: 'RUN LIGHTING BENCH',
        icon: RoomSvg.scan,
        onRun: _runBench,
        hint: _layoutHint,
      ),
      middleBody: _simSection(state),
      resultsExtra: resultsExtra,
      resultsBody: _results(state),
      applyEnabled: !applyBlocked,
      applyBlockedReason: applyValidation.hasHardLayoutConflicts
          ? 'Fix overlaps or blocked doorways before applying.'
          : (noOp ? 'Improved layout matches your room — nothing to apply.' : null),
      onApply: applyImproved,
      onRefresh: _rebuild,
      desktopControls: _desktopControls(state),
      desktopViewport: _desktopViewport(state),
      desktopInspect: _desktopInspect(
        state,
        resultsExtra: resultsExtra,
        onApply: applyBlocked ? null : applyImproved,
        applyBlockedReason: applyValidation.hasHardLayoutConflicts
            ? 'Fix overlaps or blocked doorways before applying.'
            : (noOp ? 'Improved layout matches your room — nothing to apply.' : null),
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
            BenchVariantChips(
              selected: _layoutVariant,
              onChanged: _setLayoutVariant,
              ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _roomView == _View.twoD,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _roomView = _View.twoD),
                ),
                BenchChip(
                  label: '3D',
                  selected: _roomView == _View.threeD,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _roomView = _View.threeD),
                ),
                BenchChip(
                  label: 'Compare',
                  selected: _roomView == _View.compare,
                  color: AppColors.lightingColor,
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
            BenchVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _simViz == LightingVizMode.topDown2D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
                ),
                BenchChip(
                  label: '3D',
                  selected: _simViz == LightingVizMode.orbit3D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.orbit3D),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const BenchLegend(caption: 'Illuminance'),
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
              'My Room vs Improved under your Rig Auto-Rig mix.',
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
                  selected: _simViz == LightingVizMode.topDown2D,
                  color: AppColors.lightingColor,
                  onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
                ),
                BenchChip(
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
            BenchInspectLockBlock(furniture: _furnitureFor(BenchLayoutKind.myRoom)),
            Text(
              _roomView == _View.compare
                  ? 'My Room vs Improved'
                  : switch (_layoutVariant) {
                      BenchLayoutKind.myRoom =>
                        (_layouts?.fellBackToSample ?? false)
                            ? 'Reference sample — Rig is empty (not your room)'
                            : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                      BenchLayoutKind.improved =>
                        _layouts?.improvedCaption ?? 'Improved · Auto-Rig',
                      BenchLayoutKind.sample =>
                        'Sample room — daylight blocked, lamp misplaced',
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
                      _layoutVariant == BenchLayoutKind.sample
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 14,
                      color: switch (_layoutVariant) {
                        BenchLayoutKind.sample => AppColors.amber,
                        BenchLayoutKind.myRoom => AppColors.cyan,
                        BenchLayoutKind.improved => AppColors.green,
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
                  child: BenchMetricTile(
                    label: 'Exposure',
                    value: m.exposureScore,
                    color: AppColors.lightingColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BenchMetricTile(
                    label: 'Task light',
                    value: m.taskIllumination * 100,
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BenchMetricTile(
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
  /// Rig. Pushing a layout back is the explicit Apply action under the results.
  void _setLayoutVariant(BenchLayoutKind next) {
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
        BenchVariantChips(
          selected: _layoutVariant,
          onChanged: _setLayoutVariant,
          ),
        BenchViewChips(
          children: [
            BenchChip(
              label: '2D',
              selected: _roomView == _View.twoD,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _roomView = _View.twoD),
            ),
            BenchChip(
              label: '3D',
              selected: _roomView == _View.threeD,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _roomView = _View.threeD),
            ),
            BenchChip(
              label: 'Compare',
              selected: _roomView == _View.compare,
              color: AppColors.lightingColor,
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
                    ? 'My Room vs Improved — same Auto-Rig mix as Rig'
                    : switch (_layoutVariant) {
                        BenchLayoutKind.myRoom =>
                          (_layouts?.fellBackToSample ?? false)
                              ? 'Reference room — your Rig is empty'
                              : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                        BenchLayoutKind.improved =>
                          _layouts?.improvedCaption ??
                              'Improved — your room, Auto-Rig layout',
                        BenchLayoutKind.sample =>
                          'Sample room — daylight blocked, lamp misplaced',
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
                                  benchInspectBlurb(item, mode: 'lighting'),
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
                        _layoutVariant == BenchLayoutKind.sample
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 14,
                        color: switch (_layoutVariant) {
                          BenchLayoutKind.sample => AppColors.amber,
                          BenchLayoutKind.myRoom => AppColors.cyan,
                          BenchLayoutKind.improved => AppColors.green,
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
        BenchVariantChips(
          selected: _simVariant,
          onChanged: (v) => setState(() => _simVariant = v),
        ),
        BenchViewChips(
          children: [
            BenchChip(
              label: '2D',
              selected: _simViz == LightingVizMode.topDown2D,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _simViz = LightingVizMode.topDown2D),
            ),
            BenchChip(
              label: '3D',
              selected: _simViz == LightingVizMode.orbit3D,
              color: AppColors.lightingColor,
              onTap: () => setState(() => _simViz = LightingVizMode.orbit3D),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const BenchLegend(caption: 'Illuminance'),
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
            Expanded(child: BenchMetricTile(label: 'Exposure', value: m.exposureScore, color: AppColors.lightingColor)),
            const SizedBox(width: 8),
            Expanded(child: BenchMetricTile(label: 'Task light', value: m.taskIllumination * 100, color: AppColors.amber)),
            const SizedBox(width: 8),
            Expanded(child: BenchMetricTile(label: 'Shadows', value: m.shadowRatio * 100, color: AppColors.red, invert: true)),
          ],
        ),
      ],
    );
  }

  /// Validate the layout the results header is actually showing, so the badge,
  /// the score rings, and the check rows all describe the same furniture.
  BenchmarkValidation _validationForSimVariant(AppState state) {
    final kind = _step == _LightStep.results ? BenchLayoutKind.improved : _simVariant;
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
    final delta =
        (opt.exposureScore - base.exposureScore).round();
    final deltaLabel = delta >= 0 ? '+$delta' : '$delta';
    return BenchResultsCard(
      title: 'Lighting Exposure Bench',
      accentColor: AppColors.lightingColor,
      validation: validation,
      whyReasons: _layouts?.improvedReasons ?? const [],
      rings: [
        BenchScoreRingSpec(score: base.exposureScore, color: AppColors.cyan, label: 'My Room'),
        BenchScoreRingSpec(score: opt.exposureScore, color: AppColors.lightingColor, label: 'Improved'),
      ],
      summaryText:
          'Exposure $deltaLabel · '
          'Shadows ${((base.shadowRatio - opt.shadowRatio) * 100).toStringAsFixed(0)} pts · '
          'Task light +${((opt.taskIllumination - base.taskIllumination) * 100).toStringAsFixed(0)}',
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
