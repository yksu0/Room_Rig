// lib/widgets/lighting_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../services/bench_layouts.dart';
import '../services/lighting_simulator.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'bench_panel_scaffold.dart';
import 'bench_room_views.dart';
import 'glass_card.dart';
import 'lighting_field_painter.dart';
import 'room_icons.dart';

enum _LightStep { layout, simulate, results }
enum _View { twoD, threeD }

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

  bool _running = false;
  double _progress = 0;
  bool _showResults = false;
  bool _ready = false;

  BenchLayouts? _layouts;
  int _seenFocusToken = 0;
  LightingSimSnapshot? _myRoomSim;
  LightingSimSnapshot? _improvedSim;
  LightingSimSnapshot? _sampleSim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
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
      roomFurniture: state.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _layouts = layouts;
    _myRoomSim = LightingSimulator.build(furniture: layouts.myRoom, optimized: false);
    _improvedSim = LightingSimulator.build(furniture: layouts.improved, optimized: true);
    _sampleSim = LightingSimulator.build(furniture: layouts.sample, optimized: false);
    _ready = true;
    if (resetStep) {
      _step = _LightStep.layout;
      // A pending focus request (the Rig's "Sim Prototype" button) wins once;
      // after that a reset lands back on the user's own room.
      final pending = state.benchLayoutFocusToken != _seenFocusToken;
      final kind = pending ? state.benchLayoutFocus : BenchLayoutKind.myRoom;
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = kind;
      _simVariant = kind;
      _showResults = false;
    }
  }

  /// Picks up Rig edits so the light field always describes the current room.
  /// Called from build, so it must not call setState.
  void _syncFromState(AppState state) {
    if (state.currentTab != benchTabIndex) return;
    if (state.benchLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = state.benchLayoutFocus;
      _simVariant = state.benchLayoutFocus;
      _selectedFurnitureId = null;
    }
    final fp = BenchLayoutBuilder.fingerprintOf(
      state.furniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (_layouts != null && fp == _layouts!.fingerprint) return;
    _recompute(state, resetStep: false);
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
      : 'Lights the furniture in your Rig right now, then compares it against an optimized rearrange of the same room.';

  LightingSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case BenchLayoutKind.improved:
        return _improvedSim;
      case BenchLayoutKind.sample:
        return _sampleSim;
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

  Future<void> _runBench() async {
    // Always start from the room as it stands right now.
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _running = true;
      _showResults = false;
      _progress = 0;
      _step = _LightStep.simulate;
      _simVariant = BenchLayoutKind.myRoom;
    });
    for (int i = 1; i <= 20; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() {
        _progress = i / 20;
        if (i == 10) _simVariant = BenchLayoutKind.improved;
      });
    }
    if (!mounted) return;
    // Bench → Rig only happens on the explicit Apply action below the results,
    // so finishing a run never silently replaces the user's layout.
    setState(() {
      _running = false;
      _showResults = true;
      _step = _LightStep.results;
      _simVariant = BenchLayoutKind.improved;
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

    return BenchPanelScaffold(
      accentColor: AppColors.lightingColor,
      step: _stepIndex,
      stepLabels: const ['1. Layout', '2. Light Field', '3. Results'],
      resultsEnabled: _showResults,
      running: _running,
      onStepChanged: (i) => setState(() => _step = _stepFromIndex(i)),
      layoutBody: _layoutSection(state),
      layoutRunAction: BenchRunAction(
        buttonLabel: 'RUN LIGHTING BENCH',
        icon: RoomSvg.scan,
        onRun: _running ? null : _runBench,
        hint: _layoutHint,
      ),
      middleBody: _simSection(state),
      progress: _progress,
      progressLabel: 'Tracing daylight + task lamps',
      resultsExtra: noOp
          ? benchImprovedNoOpBanner(
              message:
                  'Improved layout matches your room — lighting is already as good as the optimizer found.',
            )
          : null,
      resultsBody: _results(state),
      applyEnabled: !applyBlocked,
      applyBlockedReason: applyValidation.hasHardLayoutConflicts
          ? 'Fix overlaps or blocked doorways before applying.'
          : (noOp ? 'Improved layout matches your room — nothing to apply.' : null),
      onApply: () async {
        if (!await confirmBenchApply(context, validation: applyValidation)) return;
        if (!context.mounted) return;
        state.applyFurnitureLayout(
          _furnitureFor(BenchLayoutKind.improved),
          markOptimized: true,
        );
        showBenchApplySnackBar(
          context,
          message: 'Improved lighting layout applied to Rig',
          accentColor: AppColors.lightingColor,
          onOpenRig: () => state.setTab(2),
        );
      },
      onRefresh: _rebuild,
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
          trailing: [
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
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (_layoutVariant) {
                  BenchLayoutKind.myRoom => (_layouts?.fellBackToSample ?? false)
                      ? 'Reference room — your Rig is empty'
                      : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                  BenchLayoutKind.improved => 'Improved — your room, rearranged for light',
                  BenchLayoutKind.sample => 'Sample room — daylight blocked, lamp misplaced',
                },
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 12),
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
                          '${_layoutVariant.name}_${_roomView.name}_${_layouts?.fingerprint ?? ''}',
                        ),
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
                                builder: (cam) => CustomPaint(
                                  painter: BenchRoom3DPainter(
                                    roomWidth: room.gridCols.toDouble(),
                                    roomDepth: room.gridRows.toDouble(),
                                    roomHeight: 2.8,
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
          trailing: [
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
    // Before / after are your room and the optimizer's rearrange of it.
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final sample = _sampleSim?.metrics;
    return BenchResultsCard(
      title: 'Lighting Exposure Bench',
      validation: validation,
      rings: [
        BenchScoreRingSpec(score: base.exposureScore, color: AppColors.cyan, label: 'My Room'),
        BenchScoreRingSpec(score: opt.exposureScore, color: AppColors.lightingColor, label: 'Improved'),
        if (sample != null)
          BenchScoreRingSpec(score: sample.exposureScore, color: AppColors.amber, label: 'Sample')
        else
          BenchScoreRingSpec(score: state.lightingScore, color: AppColors.green, label: 'Score'),
      ],
      summaryText:
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

  // Silence unused warning — parent scroll can key off this later if needed.
  bool get isOrbitDragging => _orbitDragging;

}
